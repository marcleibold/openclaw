# AGENTS.md

## openclaw

Personal AI assistant based on [OpenClaw](https://docs.openclaw.ai), deployed on the k3s cluster in the `openclaw` namespace. Communicates via Matrix (Synapse) at `matrix.leibold.tech` and exposes a Control UI on port 18789.

## Repo structure

```
openclaw/
  AGENTS.md               # AI agent coordination (this file)
  ARCHITECTURE.md         # System architecture and deployment topology
  DESIGN.md               # Design decisions and rationale
  CONTRIBUTING.md         # Commit, branch, and documentation conventions
  TODO.md                 # Open tasks and technical debt
  application.yaml        # ArgoCD Application definition
  resources/
    deployment.yaml       # Kubernetes Deployment (OpenClaw gateway)
    pvc.yaml              # PersistentVolumeClaim (openclaw-home-pvc)
    secret.yaml           # SealedSecret for gateway token + provider API keys
    configmap.yaml        # ConfigMap for openclaw.json + AGENTS.md
    service.yaml          # ClusterIP Service on port 18789
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

- **Repo**: [openclaw/openclaw](https://github.com/openclaw/openclaw)
- **Docs**: [docs.openclaw.ai](https://docs.openclaw.ai)
- **License**: MIT
- **Image**: `ghcr.io/openclaw/openclaw:2026.4.12-slim` (pre-built, no custom image)

## ArgoCD

- **App name**: `openclaw`
- **Namespace**: `openclaw`
- **Repo**: `marcleibold/openclaw` (private, personal account)
- **Sync**: automated, prune, selfHeal

Apply the ArgoCD Application to the cluster once (or via the argo-cd app-of-apps if one exists):

```bash
kubectl apply -f application.yaml -n argo-cd
```

## Docker image

No custom image build needed. Uses the pre-built OpenClaw image:

- **Image**: `ghcr.io/openclaw/openclaw:2026.4.12-slim`
- **Base**: Node.js 24 on Bookworm
- **Registry**: GHCR (openclaw org)

## Configuration

OpenClaw is configured via `openclaw.json` (in the ConfigMap) and environment variables (in the Secret).

### Environment variables (Secret)

| Key | Purpose |
|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | Token for Control UI auth (auto-generated) |
| `MINIMAX_API_KEY` | MiniMax API key |
| `ANTHROPIC_API_KEY` | Optional: Anthropic API key (Claude) |
| `OPENAI_API_KEY` | Optional: OpenAI API key |

### openclaw.json (ConfigMap)

The base config enables local mode with token auth. Matrix channel config is added here.

### Matrix channel config example

Add to `openclaw.json` in the ConfigMap:

```json5
{
  channels: {
    matrix: {
      enabled: true,
      homeserver: "https://matrix.leibold.tech",
      accessToken: "<MATRIX_ACCESS_TOKEN>",
      encryption: true,
      dm: { policy: "allowlist", allowFrom: ["@mleibold:matrix.leibold.tech"] },
      groupPolicy: "allowlist",
      groupAllowFrom: ["@mleibold:matrix.leibold.tech"],
      autoJoin: "allowlist",
      autoJoinAllowlist: ["*"]
    }
  },
  agents: {
    defaults: {
      model: { primary: "minimax/MiniMax-M2.7" }
    }
  }
}
```

### Secrets

The `openclaw-secrets` Secret stores gateway token and provider API keys. Since this repo uses sealed-secrets, regenerate it with:

```bash
kubectl create secret generic openclaw-secrets \
  --namespace openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  --from-literal=MINIMAX_API_KEY="<your-key>" \
  --dry-run=client -o yaml | \
  /tmp/kubeseal --cert /tmp/sealed-secrets-cert.pem --format yaml > resources/secret.yaml
```

## Networking

- **Control UI**: port 18789 via ClusterIP Service (`kubectl port-forward svc/openclaw 18789:18789 -n openclaw`)
- **Matrix**: outbound HTTPS to `matrix.leibold.tech`
- **LLM providers**: outbound HTTPS to `api.minimax.io` (and others)
- All communication is outbound-initiated — no ingress or Ingress needed

## Persistence

- **PVC**: `openclaw-home-pvc` (10Gi, `local-path` storageClass)
- **Path**: `/home/node/.openclaw/` (uid 1000)
- **Contents**: config, credentials, Matrix crypto store, session state
- **Node binding**: uses `local-path` on whatever node the pod lands on

## Control UI access

```bash
kubectl port-forward svc/openclaw 18789:18789 -n openclaw
```

Then open http://localhost:18789 in your browser. Use the gateway token to authenticate:

```bash
kubectl get secret openclaw-secrets -n openclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' | base64 -d && echo
```

## E2EE (Matrix)

Matrix E2EE is handled by the `matrix-js-sdk`. On first deploy:
1. Complete device verification in your Element client when the bot user appears
2. Cross-signing is bootstrapped automatically on startup if not already verified

E2EE state lives in the PVC. Deleting the PVC means re-verifying all Matrix devices.

## Notes

- The `application.yaml` is not synced by ArgoCD itself — apply manually or via an app-of-apps pattern
- No SSH access in the OpenClaw image
- The bot runs as non-root (uid 1000) with a read-only root filesystem