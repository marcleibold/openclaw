# openclaw

Personal AI assistant based on [OpenClaw](https://docs.openclaw.ai), running on Kubernetes.

## Overview

OpenClaw is a self-hosted gateway that connects chat channels (Matrix, Telegram, Discord, etc.) to AI agents. This repo deploys it on a personal k3s cluster with Matrix as the primary chat interface and MiniMax M2.7 as the reasoning model.

## Repository Structure

```
openclaw/
├── AGENTS.md               # AI agent coordination (this file)
├── ARCHITECTURE.md         # System architecture
├── DESIGN.md               # Design decisions
├── application.yaml        # ArgoCD Application manifest
└── resources/              # Kubernetes resources
    ├── deployment.yaml     # OpenClaw gateway Deployment
    ├── pvc.yaml            # Persistent storage
    ├── secret.yaml         # SealedSecret for API keys
    ├── configmap.yaml      # ConfigMap for openclaw.json + AGENTS.md
    └── service.yaml        # ClusterIP Service on 18789
```

## Quick start

```bash
# Apply to cluster (after sealing secret with your API keys)
kubectl apply -f application.yaml -n argo-cd

# Access Control UI
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
- Namespace: `openclaw`