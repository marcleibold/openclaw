# Architecture

## Overview

This repo defines the Kubernetes deployment configuration for a [NanoBot](https://github.com/HKUDS/NanoBot) instance running on a personal k3s cluster. NanoBot is an ultra-lightweight personal AI assistant that connects to LLM providers and exposes itself through chat platform integrations ("channels").

The primary interaction channel is Matrix (Element), connecting to the self-hosted Synapse homeserver at `matrix.leibold.tech`.

## System context

```
                    ┌─────────────┐
                    │   Element    │
                    │  (client)    │
                    └──────┬──────┘
                           │ Matrix protocol (HTTPS)
                    ┌──────▼──────┐
                    │   Synapse    │
                    │  homeserver  │
                    │  (matrix ns) │
                    └──────┬──────┘
                           │ Matrix client API
                    ┌──────▼──────┐
                    │   NanoBot    │◄──── config.json (SealedSecret)
                    │  (gateway)   │
                    │ (nanobot ns) │
                    └──────┬──────┘
                           │ HTTPS (provider API)
                     ┌──────▼──────┐
                     │ LLM Provider │
                     │  (MiniMax)   │
                     └─────────────┘
```

### Component roles

| Component | Role | Location |
|---|---|---|
| **Element** | Matrix chat client (desktop/mobile) | User device |
| **Synapse** | Matrix homeserver, message routing, E2EE | `matrix` namespace, `matrix.leibold.tech` |
| **NanoBot** | AI assistant gateway, receives Matrix messages, calls LLM, responds | `nanobot` namespace |
| **LLM Provider** | Language model inference (MiniMax M2.7) | External (`api.minimax.io`) |

## Cluster topology

```
k3s cluster (3 nodes)
├── hp-elitedesk  (control-plane, 192.168.178.99)
├── c-nuc7        (worker, 192.168.179.5)
└── rpi3          (worker, 192.168.178.37)
```

NanoBot runs on `hp-elitedesk` (amd64, control-plane node) via `nodeSelector`. It does not require GPU or specific hardware beyond amd64. The rpi3 (arm) node is excluded by default since the Docker image is built for amd64 only.

## Kubernetes resources

### Deployment (`resources/deployment.yaml`)

- Single replica, `Recreate` strategy (no concurrent sessions)
- Runs `nanobot gateway` as the container entrypoint
- Pinned to `hp-elitedesk` via `nodeSelector`
- Mounts `config.json` from a SealedSecret as a read-only file
- Mounts a PVC for persistent runtime data (Matrix sync state, E2EE keys)
- Exec-based startup and liveness probes (process health check)
- Resource requests: 1m CPU / 32Mi memory (minimal, to fit on overcommitted node)
- Resource limits: 1 CPU / 1Gi memory
- No HTTP port exposed — the gateway does not start a web server

### PersistentVolumeClaim (`resources/pvc.yaml`)

- 1Gi on `local-path` storageClass (pinned to `hp-elitedesk`)
- Stores: Matrix sync tokens, E2EE device keys, workspace data, memory database
- Uses `local-path` instead of `ssd` (NFS-backed) because matrix-nio's SQLite E2EE store hangs on NFS file locking

### SealedSecret (`resources/secret.yaml`)

- Contains `config.json` with all sensitive configuration
- LLM provider API keys, Matrix access token, device ID
- Must be re-sealed when config changes (see AGENTS.md for workflow)

## Docker image

### Build pipeline

```
Dockerfile change on master
        │
        ▼
GitHub Actions (.github/workflows/docker.yml)
        │
        ▼
ghcr.io/marcleibold/nanobot:latest
ghcr.io/marcleibold/nanobot:sha-<commit>
```

### Image contents

The custom Dockerfile:

1. **Base**: `ghcr.io/astral-sh/uv:python3.12-bookworm-slim`
2. **Clones** upstream NanoBot at a pinned version (`NANOBOT_VERSION` build arg)
3. **Installs** `nanobot-ai[matrix]` for Matrix E2EE support via `matrix-nio[e2e]`
4. **Entrypoint**: `nanobot gateway`

### Why a custom image?

- Upstream NanoBot does not publish pre-built Docker images
- Matrix E2EE support (`matrix-nio[e2e]`) is an optional dependency not in the base install
- Pinning the version ensures reproducible deployments

## Data flow

### Message lifecycle

1. User sends message in Element
2. Synapse routes message to nanobot's Matrix account
3. NanoBot gateway receives message via Matrix client sync
4. NanoBot processes message, calls LLM provider API
5. LLM responds with generated text
6. NanoBot sends response back via Matrix client API
7. User sees response in Element

### Persistence

NanoBot writes runtime state to `/root/.nanobot/`:

| Path | Purpose | Persistence |
|---|---|---|
| `config.json` | App configuration | Secret mount (read-only) |
| `matrix-store/` | Matrix sync tokens, E2EE keys | PVC |
| `workspace/` | Agent workspace, memory | PVC |
| `*.db` | SQLite databases (memory, etc.) | PVC |

## Network dependencies

| Direction | From | To | Protocol | Purpose |
|---|---|---|---|---|
| Outbound | NanoBot | `matrix.leibold.tech` | HTTPS | Matrix client API |
| Outbound | NanoBot | `api.minimax.io` | HTTPS | LLM inference |

NanoBot acts as a Matrix client — all communication is outbound-initiated. No ingress or inbound traffic is required.

## GitOps

All cluster state is managed via ArgoCD:

- **Source**: `marcleibold/nanobot` repo, `resources/` directory
- **Sync**: Automated with prune and self-heal
- **Namespace**: `nanobot` (auto-created)
- The `application.yaml` must be applied manually to bootstrap

See `AGENTS.md` for operational details.
