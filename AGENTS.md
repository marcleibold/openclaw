# AGENTS.md

## nanobot

Personal AI assistant based on [HKUDS/NanoBot](https://github.com/HKUDS/NanoBot), deployed on the k3s cluster in the `nanobot` namespace. Communicates via the Matrix (Synapse) homeserver at `matrix.leibold.tech`.

## Repo structure

```
nanobot/
  AGENTS.md               # AI agent coordination (this file)
  ARCHITECTURE.md         # System architecture and deployment topology
  DESIGN.md               # Design decisions and rationale
  CONTRIBUTING.md         # Commit, branch, and documentation conventions
  TODO.md                 # Open tasks and technical debt
  Dockerfile              # Custom nanobot image with Matrix E2EE support
  application.yaml        # ArgoCD Application definition
  .github/
    workflows/
      docker.yml          # CI: build and push Docker image to GHCR
  resources/
    deployment.yaml       # Kubernetes Deployment (gateway mode)
    pvc.yaml              # PersistentVolumeClaim for runtime data
    secret.yaml           # SealedSecret for config.json
```

## Key documentation

| File | Purpose |
|---|---|
| `AGENTS.md` | Quick reference for AI agents — repo layout, deployment, secrets |
| `ARCHITECTURE.md` | Full system architecture, component diagram, data flow |
| `DESIGN.md` | Design decisions, trade-offs, alternatives considered |
| `CONTRIBUTING.md` | Commit message format, branch naming, code style |
| `TODO.md` | Tracked open work items and technical debt |

## Upstream project

- **Repo**: [HKUDS/NanoBot](https://github.com/HKUDS/NanoBot)
- **Version**: `v0.1.4.post6` (pinned in `Dockerfile`)
- **License**: MIT
- **PyPI**: `nanobot-ai`
- **No pre-built Docker image** — we build our own via GitHub Actions

## ArgoCD

- **App name**: `nanobot`
- **Namespace**: `nanobot`
- **Repo**: `marcleibold/nanobot` (private, personal account)
- **Sync**: automated, prune, selfHeal

Apply the ArgoCD Application to the cluster once (or via the argo-cd app-of-apps if one exists):

```bash
kubectl apply -f application.yaml -n argo-cd
```

## Docker image

The custom Docker image is built from `Dockerfile` in this repo. It:

1. Uses `ghcr.io/astral-sh/uv:python3.12-bookworm-slim` as the base
2. Clones upstream NanoBot at a pinned version tag
3. Installs with `.[matrix]` extras for Matrix E2EE support
4. Runs `nanobot gateway` as the default command

**Registry**: `ghcr.io/marcleibold/nanobot`
**Tags**: `latest`, `sha-<commit>`

The GitHub Actions workflow (`.github/workflows/docker.yml`) builds and pushes on changes to `Dockerfile` on the `master` branch, or on manual dispatch.

## Configuration

nanobot is configured via `config.json`, which contains:

- **LLM provider** credentials (API keys)
- **Matrix channel** settings (homeserver, userId, accessToken, deviceId)
- **Agent defaults** (model, provider)

This config is stored as a SealedSecret (`nanobot-config`) and mounted into the pod at `/root/.nanobot/config.json`.

### Config structure (template)

```json
{
  "providers": {
    "minimax": {
      "apiKey": "<MINIMAX_API_KEY>"
    }
  },
  "agents": {
    "defaults": {
      "model": "minimax-m2.7",
      "provider": "minimax"
    }
  },
  "channels": {
    "matrix": {
      "enabled": true,
      "homeserver": "https://matrix.leibold.tech",
      "userId": "@nanobot:matrix.leibold.tech",
      "accessToken": "<MATRIX_ACCESS_TOKEN>",
      "deviceId": "NANOBOT01",
      "e2eeEnabled": true,
      "allowFrom": ["@mleibold:matrix.leibold.tech"],
      "groupPolicy": "mention"
    }
  },
  "gateway": {
    "port": 18790
  }
}
```

## Secrets

Secrets are encrypted with Sealed Secrets. See the root `AGENTS.md` at `/home/spof/Projects/AGENTS.md` for the kubeseal workflow.

The `nanobot-config` secret contains a single key `config.json` with the full nanobot configuration.

### Creating the SealedSecret

```bash
kubectl create secret generic nanobot-config \
  --namespace nanobot \
  --from-file=config.json=config-plain.json \
  --dry-run=client -o yaml | \
  /tmp/kubeseal --cert /tmp/sealed-secrets-cert.pem --format yaml > resources/secret.yaml
```

## Networking

- **No HTTP server**: the gateway does not expose an HTTP port (the `port` in config is unused by the current NanoBot version)
- **No Service or Ingress**: since there is no listening port, no Kubernetes Service is needed
- **Matrix connection**: outbound HTTPS to `matrix.leibold.tech`
- NanoBot acts as a Matrix client — all communication is outbound-initiated, no inbound traffic required

## Persistence

- **PVC**: `nanobot-data` (1Gi, `local-path` storageClass, pinned to `hp-elitedesk`)
- Stores Matrix sync state (`matrix-store`), E2EE keys, workspace data
- Uses local-path instead of NFS because matrix-nio's SQLite E2EE store hangs on NFS file locking

## SSH access to cluster nodes

The bot can SSH *out* to nodes (`openssh-client` is installed). It cannot be reached via SSH — no server is running.

SSH config and keys are stored on the PVC at `/root/.nanobot/ssh/`, which is symlinked to `~/.ssh` inside the container. Keys and `known_hosts` survive pod restarts. The bot runs as `root`, so `~/.ssh` → `/root/.nanobot/ssh`.

Initial key provisioning is a one-time manual step — see `TODO.md`.

## Notes

- The `application.yaml` is not synced by ArgoCD itself — it must be applied manually or via an app-of-apps pattern.
- The Matrix account (`@nanobot:matrix.leibold.tech`) is registered on Synapse with device ID `NANOBOT01`.
- E2EE requires a stable `deviceId` and persistent `matrix-store` directory — never delete the PVC without re-verifying E2EE sessions.
