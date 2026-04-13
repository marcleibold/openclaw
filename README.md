# openclaw

Personal AI assistant based on [OpenClaw](https://docs.openclaw.ai), running on Kubernetes.

## Currently Deployed Versions

| Component | Version | Image |
|---|---|---|
| OpenClaw | 2026.4.12-slim | `ghcr.io/openclaw/openclaw:2026.4.12-slim` |
| Matrix (Synapse) | v1.127.1 | `matrixdotorg/synapse:v1.127.1` |

## Overview

OpenClaw is a self-hosted gateway that connects chat channels (Matrix, Telegram, Discord, etc.) to AI agents. This repo deploys it on a personal k3s cluster with Matrix as the primary chat interface and MiniMax M2.7 as the reasoning model.

## ArgoCD Application

The ArgoCD Application for openclaw is managed in the [cluster repository](https://github.com/SP0Fs/cluster) under `applications/`. Do not apply `application.yaml` from this repo - it is deprecated.

## Secrets

The `openclaw-secrets` SealedSecret stores gateway token and provider API keys. To regenerate:

```bash
kubectl create secret generic openclaw-secrets \
  --namespace openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  --from-literal=MINIMAX_API_KEY="<your-key>" \
  --dry-run=client -o yaml | \
  /tmp/kubeseal --cert /tmp/sealed-secrets-cert.pem --format yaml > resources/secret.yaml
```

## Quick start

```bash
# Access Control UI (after deployment via cluster repo)
kubectl port-forward svc/openclaw 18789:18789 -n openclaw
open http://localhost:18789

# Get gateway token
kubectl get secret openclaw-secrets -n openclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' | base64 -d && echo
```

## Features

- Matrix messaging integration (E2EE)
- MiniMax M2.7 reasoning model
- Control UI on port 18789
- Persistent storage for session state
- Multi-channel support (Telegram, Discord, etc. available via plugins)

## Links

- Docs: [docs.openclaw.ai](https://docs.openclaw.ai)
- Source: [github.com/marcleibold/openclaw](https://github.com/marcleibold/openclaw)
- Cluster repo: [github.com/SP0Fs/cluster](https://github.com/SP0Fs/cluster)
- Namespace: `openclaw`