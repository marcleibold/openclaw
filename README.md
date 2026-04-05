# nanobot

Personal AI assistant for the SP0Fs cluster.

## Overview

nanobot is an AI assistant running on Kubernetes, providing home automation integration, GitHub management, and task automation.

## Repository Structure

```
nanobot/
├── Dockerfile           # Container image
├── entrypoint.sh        # Startup script
├── application.yaml     # ArgoCD Application manifest
├── resources/           # Kubernetes resources
└── (nanobot codebase)
```

## Features

- Matrix messaging integration
- GitHub integration (gh CLI)
- Kubernetes management
- Cron/scheduling
- Memory and context management

## Links

- Source: https://github.com/marcleibold/nanobot
- Namespace: `nanobot`
