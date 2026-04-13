# Design Decisions

This document captures the key design decisions, trade-offs, and alternatives considered for the OpenClaw deployment.

## D1: Pre-built OpenClaw image vs. custom build

**Decision**: Use the pre-built `ghcr.io/openclaw/openclaw:2026.4.12-slim` image.

**Context**: OpenClaw publishes official Docker images to GHCR. No custom image build is needed since the bot is purely a gateway — it receives Matrix messages, calls an LLM, and responds. No custom nanobot code to run.

**Alternatives considered**:

1. **Fork and build custom image** — Over-engineering; no patches needed.
2. **Build from source** — `npm install` from upstream repo would add CI complexity without benefit.

**Trade-offs**:
- (+) Zero maintenance — image updates are managed upstream
- (+) Faster deploys — no build step in CI
- (+) SHA-pinned image for traceability
- (-) Must wait for upstream to publish new versions for bug fixes

## D2: Configuration via ConfigMap + Secret (env vars)

**Decision**: Store non-sensitive config in a ConfigMap (`openclaw.json`) and sensitive values (API keys, gateway token) as env vars in a Secret.

**Context**: OpenClaw's configuration model uses `openclaw.json` for channels, agents, and provider settings. Sensitive values (API keys, Matrix access token) live in env vars.

**Alternatives considered**:

1. **SealedSecret for entire config** — The old nanobot approach. OpenClaw config is large and complex; env vars are the native secret mechanism.
2. **External secret manager (Vault, ESO)** — Over-engineered for a single-user personal deployment.

**Trade-offs**:
- (+) ConfigMap is visible in git — full visibility into non-sensitive settings
- (+) Env vars are the native OpenClaw secret mechanism
- (-) ConfigMap changes trigger redeploys (ArgoCD reconciles automatically)
- (-) Matrix access token is in ConfigMap (not a secret), but it's a Matrix token, not a provider key

## D3: Matrix as the primary chat channel

**Decision**: Use Matrix (via the self-hosted Synapse instance) as the primary chat interface.

**Context**: The cluster already runs Synapse at `matrix.leibold.tech`. OpenClaw supports Matrix as a bundled channel plugin with E2EE via `matrix-js-sdk`.

**Alternatives considered**:

1. **Telegram** — Simpler setup, but adds an external dependency. Matrix is already self-hosted.
2. **Discord** — Requires a public bot application. Matrix is fully self-hosted and private.
3. **CLI only** — No persistent chat history, no mobile access.

**Trade-offs**:
- (+) Fully self-hosted, no external service dependency for the chat layer
- (+) E2EE for message privacy
- (+) Existing Matrix client apps (Element) on all devices
- (-) Matrix E2EE adds complexity (device verification, key backup, persistent state)

## D4: Persistent volume for runtime state

**Decision**: Use a PVC for OpenClaw's runtime data directory.

**Context**: OpenClaw stores Matrix sync tokens, E2EE device keys (via IndexedDB snapshots), session state, and workspace data on the filesystem. Losing this data means:
- Matrix E2EE sessions break (must re-verify all devices)
- Conversation memory is lost
- Sync position resets (may re-process old messages)

**Alternatives considered**:

1. **EmptyDir** — Data lost on pod restart. Unacceptable for E2EE keys.
2. **HostPath** — Ties the pod to a specific node. Fragile.
3. **External database** — OpenClaw uses local filesystem; would require upstream changes.

**Trade-offs**:
- (+) Data survives pod restarts and rescheduling
- (+) Standard pattern used by other deployments in the cluster
- (-) 10Gi allocation may need adjustment over time
- (-) PVC is node-bound with `ReadWriteOnce` — pod cannot float freely between nodes

## D5: Gateway mode (not CLI)

**Decision**: Run OpenClaw in `gateway run` mode as a long-running service.

**Context**: OpenClaw has two primary modes:
- `openclaw shell` — Interactive local CLI
- `openclaw gateway run` — Long-running daemon that connects to configured channels

**Rationale**: Gateway mode is the only way to maintain persistent channel connections (Matrix). The CLI mode is for ad-hoc local use.

## D6: HTTP health probes

**Decision**: Use HTTP `GET /healthz` (liveness) and `GET /readyz` (readiness) probes.

**Context**: OpenClaw's gateway starts an HTTP server on port 18789 for the Control UI and health endpoints. This is a proper HTTP server unlike nanobot's gateway.

**Trade-offs**:
- (+) Standard Kubernetes HTTP probe — reliable, no exec overhead
- (+) Readiness probe gates traffic after startup is complete
- (+) Both probe endpoints are unauthenticated

## D7: ClusterIP Service for Control UI

**Decision**: Create a ClusterIP Service on port 18789 instead of relying solely on `kubectl port-forward`.

**Context**: The Control UI runs on port 18789. Since the gateway binds to `loopback` (not a routable IP), direct cluster access requires a port-forward. The Service enables in-cluster service discovery and port-forward from a stable target.

**Trade-offs**:
- (+) Stable `svc/openclaw:18789` target for port-forwarding
- (+) In-cluster access if gateway bind is changed to `lan`
- (-) No external Ingress needed since all access is via port-forward

## D8: local-path storageClass (not ssd/NFS)

**Decision**: Use `local-path` storageClass.

**Context**: OpenClaw's Matrix E2EE support uses `matrix-js-sdk` with IndexedDB snapshots stored to the filesystem. The SDK relies on file-level locking which does not work reliably over NFS.

**Alternatives considered**:

1. **ssd (NFS-backed)** — Default storageClass. Causes issues with IndexedDB snapshots on NFS.
2. **EmptyDir** — No persistence. E2EE keys would be lost.
3. **HostPath** — Equivalent to local-path but less managed.

**Trade-offs**:
- (+) IndexedDB snapshots work correctly on local filesystem
- (+) Lower latency for database operations
- (-) Data is tied to whatever node the pod lands on
- (-) No redundancy

## D9: MiniMax direct provider

**Decision**: Use MiniMax as the LLM provider via OpenClaw's built-in `minimax` provider.

**Context**: OpenClaw natively supports MiniMax as a first-class provider with `MiniMax-M2.7` as the default model. It uses the Anthropic-compatible API at `api.minimax.io`.

**Alternatives considered**:

1. **OpenRouter** — Access to 100+ models but adds a middleman with latency and cost markup.
2. **Anthropic direct** — Claude quality but different cost model.

**Trade-offs**:
- (+) Lower latency — direct API calls, no intermediary
- (+) Lower cost — no OpenRouter markup
- (+) Native OpenClaw provider with bundled image understanding (MiniMax-VL-01)
- (-) Limited to MiniMax models only
- OpenRouter/Claude can be added later as secondary providers

## D10: 10Gi PVC allocation

**Decision**: Allocate 10Gi for the PVC.

**Context**: OpenClaw stores:
- Matrix sync state + E2EE IndexedDB snapshots
- Session state and transcripts
- Agent workspace + memory
- Logs and media cache

**Trade-offs**:
- (+) Generous headroom for media cache and transcripts
- (+) More than the old 1Gi nanobot PVC (which was adequate but tight)
- (-) Larger allocation on local-path storage uses more node disk

## D11: Resource requests/limits (512Mi/250m CPU requests, 2Gi/1 CPU limits)

**Decision**: Set resource requests to 512Mi memory / 250m CPU with limits at 2Gi memory / 1 CPU.

**Context**: The `hp-elitedesk` node is overcommitted. OpenClaw is Node.js (not Python) and has a different memory profile than nanobot.

**Trade-offs**:
- (+) Appropriate for a Node.js gateway process
- (+) Headroom for media processing and vector search
- (-) Higher than the old nanobot requests (1m CPU) — justified by Node.js vs. Python difference
- (-) Must ensure node has capacity

## D12: Non-root container (uid 1000)

**Decision**: Run the container as non-root user (uid 1000, gid 1000).

**Context**: The official OpenClaw image runs as `node` (uid 1000). The deployment enforces this with `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, and `capabilities: drop: ALL`.

**Trade-offs**:
- (+) Security hardening — principle of least privilege
- (+) No custom image needed
- (-) Init container must also run as uid 1000 (handled with explicit securityContext)