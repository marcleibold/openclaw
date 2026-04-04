# Design Decisions

This document captures the key design decisions, trade-offs, and alternatives considered for the nanobot deployment.

## D1: Custom Docker image vs. upstream source install

**Decision**: Build a custom Docker image from the upstream NanoBot source.

**Context**: NanoBot does not publish pre-built Docker images. The upstream repo provides a `Dockerfile` that builds from source, but it does not include the optional `matrix` extras needed for E2EE.

**Alternatives considered**:

1. **Fork upstream and maintain patches** — Too much maintenance overhead for a personal project.
2. **Use upstream Dockerfile as-is** — Missing Matrix E2EE support (`matrix-nio[e2e]`).
3. **Install via pip in a generic Python image** — Works, but loses upstream build optimizations.

**Trade-offs**:

- (+) Pinned version ensures reproducibility
- (+) Matrix E2EE support included
- (+) GitHub Actions automates the build
- (-) Must manually bump `NANOBOT_VERSION` in the Dockerfile for upgrades
- (-) Build depends on upstream repo availability

## D2: Configuration via SealedSecret (config.json)

**Decision**: Store the entire `config.json` as a SealedSecret, mounted as a file.

**Context**: NanoBot's configuration model is a single JSON file at `~/.nanobot/config.json`. It contains both non-sensitive settings (model name, channel policies) and sensitive values (API keys, Matrix access token).

**Alternatives considered**:

1. **ConfigMap for non-sensitive + Secret for sensitive** — NanoBot does not support split config files or environment variable overrides for all settings. Would require an init container to merge them.
2. **Environment variables only** — NanoBot supports env vars for provider API keys, but not for Matrix channel config, agent defaults, or most other settings.
3. **External secret manager (Vault, ESO)** — Over-engineered for a single-user personal deployment.

**Trade-offs**:

- (+) Simple, single file matches NanoBot's native config model
- (+) SealedSecret is already the established pattern in this cluster
- (-) Any config change (even non-sensitive) requires re-sealing
- (-) The entire config is opaque in git (no visibility into non-sensitive values)

## D3: Matrix as the primary chat channel

**Decision**: Use Matrix (via the self-hosted Synapse instance) as the primary chat interface.

**Context**: The cluster already runs Synapse at `matrix.leibold.tech`. NanoBot supports Matrix as a first-class channel with E2EE support.

**Alternatives considered**:

1. **Telegram** — Simpler setup, but adds an external dependency. Matrix is already self-hosted.
2. **Discord** — Requires a public bot application. Matrix is fully self-hosted and private.
3. **CLI only** — No persistent chat history, no mobile access.

**Trade-offs**:

- (+) Fully self-hosted, no external service dependency for the chat layer
- (+) E2EE for message privacy
- (+) Existing Matrix client apps (Element) on all devices
- (-) Matrix E2EE adds complexity (device verification, key backup, persistent state)
- (-) NanoBot's Matrix channel is relatively new (added 2026-02-25)

## D4: Persistent volume for runtime state

**Decision**: Use a PVC for NanoBot's runtime data directory.

**Context**: NanoBot stores Matrix sync tokens, E2EE device keys, agent memory (SQLite), and workspace data on the filesystem. Losing this data means:
- Matrix E2EE sessions break (must re-verify all devices)
- Conversation memory is lost
- Sync position resets (may re-process old messages)

**Alternatives considered**:

1. **EmptyDir** — Data lost on pod restart. Unacceptable for E2EE keys.
2. **HostPath** — Ties the pod to a specific node. Fragile.
3. **External database** — NanoBot uses SQLite internally; would require upstream changes.

**Trade-offs**:

- (+) Data survives pod restarts and rescheduling
- (+) Standard pattern used by other deployments in the cluster
- (-) 1Gi allocation may need adjustment over time
- (-) PVC is node-bound with `ReadWriteOnce` — pod cannot float freely between nodes

## D5: Gateway mode (not CLI)

**Decision**: Run NanoBot in `gateway` mode as a long-running service.

**Context**: NanoBot has two primary modes:
- `nanobot agent` — Interactive CLI session
- `nanobot gateway` — Long-running daemon that connects to configured channels

**Rationale**: Gateway mode is the only way to maintain persistent channel connections (Matrix, Telegram, etc.). The CLI mode is for ad-hoc local use.

## D6: Health probes targeting /health

**Decision**: Configure startup, liveness, and readiness probes against the `/health` HTTP endpoint.

**Context**: NanoBot exposes an HTTP server on its gateway port (18790) with a `/health` endpoint.

**Trade-offs**:

- (+) Standard Kubernetes health checking
- (+) Detects hung or crashed gateway processes
- (-) Unclear whether `/health` accurately reflects Matrix channel connectivity (may report healthy even if Matrix sync is broken)
- This needs validation after initial deployment (see TODO.md)

## D7: No ingress

**Decision**: Do not expose NanoBot via ingress. The service is ClusterIP-only.

**Context**: NanoBot acts as a Matrix client — all communication is outbound-initiated. The gateway HTTP server (port 18790) is only needed internally for Kubernetes health probes. Exposing it externally would add attack surface with no functional benefit.

**Rationale**: An ingress could be added later if external API access or monitoring is needed, but for a Matrix-only deployment it is unnecessary.

## D8: GitHub Actions for image builds

**Decision**: Use GitHub Actions with GHCR for building and storing Docker images.

**Context**: The repo is on GitHub (private, `marcleibold/nanobot`). GHCR is free for private repos with GitHub Actions.

**Alternatives considered**:

1. **Build locally and push** — Manual, error-prone, no audit trail.
2. **In-cluster CI (Tekton, Woodpecker)** — Adds operational complexity.
3. **Docker Hub** — Rate limits, less integrated with GitHub.

**Trade-offs**:

- (+) Automated, triggered on Dockerfile changes
- (+) Free for private repos
- (+) SHA-tagged images for traceability
- (-) Cluster must be able to pull from GHCR (may need imagePullSecret for private packages)

## D9: MiniMax direct provider (not OpenRouter)

**Decision**: Use MiniMax as a direct LLM provider via NanoBot's built-in `minimax` provider, rather than routing through OpenRouter.

**Context**: NanoBot natively supports MiniMax as a first-class provider (added in v0.1.4, 2026-02-11). It uses the `openai_compat` backend with `api.minimax.io/v1` as the default endpoint. The initial plan was to use OpenRouter as a gateway for multi-model flexibility, but MiniMax direct is simpler for a first deployment.

**Alternatives considered**:

1. **OpenRouter** — Provides access to 100+ models (Claude, GPT-4o, Gemini, etc.) through a single API key. Adds a middleman with extra latency and cost markup.
2. **Both providers** — Configure MiniMax as primary and OpenRouter as secondary for model flexibility. Adds complexity for initial deployment.
3. **Custom provider** — Use the generic `custom` provider to point at MiniMax's API. Unnecessary since MiniMax has dedicated support.

**Trade-offs**:

- (+) Lower latency — direct API calls, no intermediary
- (+) Lower cost — no OpenRouter markup
- (+) Simpler config — only one API key needed
- (+) First-class support — NanoBot knows MiniMax model capabilities
- (-) Limited to MiniMax models only (minimax-m2.7, etc.)
- (-) No easy model switching without re-sealing the config
- OpenRouter can be added later as a secondary provider if multi-model access is needed
