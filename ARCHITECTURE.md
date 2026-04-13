# Architecture

## Overview

This repo defines the Kubernetes deployment configuration for an [OpenClaw](https://docs.openclaw.ai) gateway running on a personal k3s cluster. OpenClaw is a self-hosted gateway that connects chat channels (including Matrix) to AI agents. OpenClaw natively supports MiniMax as a model provider.

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
                    │   OpenClaw  │
                    │  (gateway)  │
                    │ (openclaw ns)│
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
| **OpenClaw** | AI assistant gateway, receives Matrix messages, calls LLM, responds | `openclaw` namespace |
| **LLM Provider** | Language model inference (MiniMax M2.7) | External (`api.minimax.io`) |

## Cluster topology

```
k3s cluster (3 nodes)
├── hp-elitedesk  (control-plane, 192.168.178.99)
├── c-nuc7        (worker, 192.168.179.5)
└── rpi3          (worker, 192.168.178.37)
```

OpenClaw runs on any amd64 node. The Docker image is built for amd64 only, excluding `rpi3` (arm).

## Kubernetes resources

### Deployment (`resources/deployment.yaml`)

- Single replica, `Recreate` strategy
- Runs `node /app/dist/index.js gateway run` as the container entrypoint
- Uses the pre-built `ghcr.io/openclaw/openclaw:2026.4.12-slim` image
- ConfigMap-mounted `openclaw.json` for base configuration
- PVC-mounted `/home/node/.openclaw/` for persistent runtime data
- HTTP liveness probe (`GET /healthz`) and readiness probe (`GET /readyz`)
- Resource requests: 512Mi memory / 250m CPU; limits: 2Gi memory / 1 CPU
- Security: non-root user (1000), read-only root filesystem, `drop: ALL` capabilities

### PersistentVolumeClaim (`resources/pvc.yaml`)

- 10Gi on `local-path` storageClass
- Stores: Matrix sync tokens, E2EE device keys, IndexedDB snapshots, session state, workspace data
- Uses `local-path` (not NFS) — OpenClaw's `matrix-js-sdk` uses IndexedDB snapshots that are sensitive to file locking semantics

### ConfigMap (`resources/configmap.yaml`)

- Contains `openclaw.json` (base gateway config) and `AGENTS.md` (agent instructions)
- Non-sensitive configuration only — no secrets in this resource

### SealedSecret (`resources/secret.yaml`)

- Contains `OPENCLAW_GATEWAY_TOKEN` and provider API keys (`MINIMAX_API_KEY`, etc.)
- Stored as a SealedSecret in this repo; regenerate with kubeseal after changes

### Service (`resources/service.yaml`)

- ClusterIP on port 18789 for the Control UI
- All outbound communication — no ingress needed

## Docker image

No custom Dockerfile needed. Uses the official pre-built image:

- **Image**: `ghcr.io/openclaw/openclaw:2026.4.12-slim`
- **Base**: Node.js 24 on Bookworm
- **Registry**: GHCR (openclaw org)

## Data flow

### Message lifecycle

1. User sends message in Element
2. Synapse routes message to openclaw's Matrix account
3. OpenClaw gateway receives message via Matrix client sync
4. OpenClaw processes message, calls LLM provider API
5. LLM responds with generated text
6. OpenClaw sends response back via Matrix client API
7. User sees response in Element

### Persistence

OpenClaw writes runtime state to `/home/node/.openclaw/`:

| Path | Purpose | Persistence |
|---|---|---|
| `openclaw.json` | Base config | ConfigMap mount (read-only) |
| `credentials/matrix/` | Matrix access tokens, cached credentials | PVC |
| `matrix/` | Matrix sync state, E2EE keys, IndexedDB snapshots | PVC |
| `workspace/` | Agent workspace, memory | PVC |
| `agents/` | Agent session state | PVC |

## Network dependencies

| Direction | From | To | Protocol | Purpose |
|---|---|---|---|---|
| Outbound | OpenClaw | `matrix.leibold.tech` | HTTPS | Matrix client API |
| Outbound | OpenClaw | `api.minimax.io` | HTTPS | LLM inference |

OpenClaw acts as a Matrix client — all communication is outbound-initiated. No ingress or inbound traffic is required.

## GitOps

All cluster state is managed via ArgoCD:

- **Source**: `marcleibold/openclaw` repo, `resources/` directory
- **Sync**: Automated with prune and self-heal
- **Namespace**: `openclaw` (auto-created)
- The `application.yaml` must be applied manually to bootstrap

See `AGENTS.md` for operational details.