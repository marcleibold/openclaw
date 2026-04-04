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

## D6: Exec-based health probes (no HTTP endpoint)

**Decision**: Use exec-based liveness and startup probes that verify the main process is alive.

**Context**: The NanoBot gateway does not start an HTTP server despite the `port` config option. The `gateway` command runs channels and the agent loop as async tasks but never binds a socket. The port number in config appears to be reserved for future use.

**Discovery**: Initial deployment used `httpGet` probes targeting `/health` on port 18790. The startup probe consistently failed with `connection refused` because no HTTP server was listening.

**Current probes**:
- **Startup probe**: `python3 -c "import os, signal; os.kill(1, 0)"` — verifies PID 1 (nanobot) is alive
- **Liveness probe**: same command, runs every 30s

**Trade-offs**:

- (+) Works with the actual gateway behavior
- (+) Simple, no dependencies
- (-) Cannot detect a hung gateway that is still running but not processing messages
- (-) No readiness probe — pod is "ready" as soon as the process starts
- Consider adding a deeper health check in the future (e.g., check Matrix sync recency via a sidecar or agent skill)

## D7: No Service or Ingress

**Decision**: Do not create a Kubernetes Service or Ingress for NanoBot.

**Context**: NanoBot acts as a Matrix client — all communication is outbound-initiated. The gateway does not expose an HTTP server, so there is no port to proxy. No inbound traffic is needed.

**Rationale**: A Service targeting a non-existent port is misleading and serves no purpose. If the upstream NanoBot adds an HTTP API in the future, a Service can be added at that time.

## D8: GitHub Actions for image builds

**Decision**: Use GitHub Actions with GHCR for building and storing Docker images.

**Context**: The repo is on GitHub (`marcleibold/nanobot`). GHCR is free with GitHub Actions.

**Alternatives considered**:

1. **Build locally and push** — Manual, error-prone, no audit trail.
2. **In-cluster CI (Tekton, Woodpecker)** — Adds operational complexity.
3. **Docker Hub** — Rate limits, less integrated with GitHub.

**Trade-offs**:

- (+) Automated, triggered on Dockerfile changes
- (+) Free with GitHub Actions
- (+) SHA-tagged images for traceability
- (-) Cluster must be able to pull from GHCR (public packages don't need imagePullSecret)

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

## D10: local-path storageClass (not ssd/NFS)

**Decision**: Use `local-path` storageClass with node pinning instead of the cluster's `ssd` storageClass.

**Context**: The `ssd` storageClass in this cluster is actually NFS-backed (`nfs-provisioner`). NanoBot's Matrix E2EE support uses `matrix-nio`, which stores encryption keys in a SQLite database. SQLite relies on file-level locking (`fcntl`), which does not work reliably over NFS.

**Discovery**: The initial deployment used `ssd` storageClass. The pod would start, begin Matrix sync, then hang in uninterruptible disk sleep (D state) when matrix-nio attempted to open its SQLite E2EE key store over NFS. The process could not be killed (SIGKILL had no effect) and the pod had to wait for the NFS timeout.

**Alternatives considered**:

1. **ssd (NFS-backed)** — Default storageClass, works for most workloads. Causes D-state hang with SQLite.
2. **EmptyDir** — No persistence across restarts. E2EE keys would be lost, requiring re-verification.
3. **HostPath** — Equivalent to local-path but less managed. No reclaim policy.

**Trade-offs**:

- (+) SQLite works correctly on local filesystem
- (+) Lower latency for database operations
- (-) Data is tied to `hp-elitedesk` node — pod cannot float between nodes
- (-) No redundancy — data is lost if the node's disk fails
- The `nodeSelector` on the deployment ensures the pod always lands on the same node as the PVC

## D11: Minimal resource requests (1m CPU / 32Mi memory)

**Decision**: Set resource requests to the minimum necessary (1m CPU, 32Mi memory) while keeping limits at 1 CPU / 1Gi.

**Context**: The `hp-elitedesk` node has 4000m total CPU with 3995m already requested by other workloads. Even 10m CPU request causes `Insufficient cpu` scheduling failures. NanoBot is bursty — mostly idle waiting for Matrix messages, then briefly active during LLM calls.

**Alternatives considered**:

1. **No requests (limits only)** — Kubernetes sets requests = limits when requests are omitted, making it worse (1 full CPU request).
2. **BestEffort (no requests or limits)** — First to be evicted under memory pressure. Too risky for E2EE state.
3. **Move to another node** — `c-nuc7` has capacity but the PVC is `local-path` on `hp-elitedesk`.

**Trade-offs**:

- (+) Pod can schedule despite the overcommitted node
- (+) Limits still cap resource usage to prevent runaway consumption
- (-) Under pressure, kubelet may throttle or OOM-kill this pod before pods with higher requests
- (-) Relies on the node having actual idle capacity despite being "99% requested"
