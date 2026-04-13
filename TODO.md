# TODO

Open tasks and technical debt, roughly ordered by priority.

## Deployment Status

- [x] OpenClaw gateway deployed and running in `openclaw` namespace
- [x] ArgoCD Application managed in cluster repo (github.com/SP0Fs/cluster)
- [x] Gateway bind changed to `lan` for kubelet probes
- [x] Default model set to `minimax/MiniMax-M2.7`

## Required Configuration

- [ ] Replace placeholder secrets in `openclaw-secrets` with real API keys
  - MINIMAX_API_KEY
  - OPENCLAW_GATEWAY_TOKEN (auto-generated on first run)
- [ ] Configure Matrix channel in `openclaw.json`:
  - homeserver: https://matrix.leibold.tech
  - userId: @openclaw:matrix.leibold.tech
  - accessToken: (from Matrix registration)
- [ ] Verify Control UI accessible at http://localhost:18789
- [ ] Verify Matrix connection — bot joins and responds to DMs

## Post-deployment verification

- [ ] Verify Matrix E2EE works (encrypted DM, verify device in Element)
- [ ] Verify PVC data persists across pod restarts (Matrix sync resumes)
- [ ] Verify memory/conversation history persists across restarts
- [ ] Verify Control UI shows correct status and chat history

## Improvements

- [ ] Pin image to SHA tag instead of versioned tag in cluster repo
- [ ] Add Prometheus metrics scraping if OpenClaw exposes them
- [ ] Add network policy to restrict egress to only matrix.leibold.tech and api.minimax.io
- [ ] Add `podDisruptionBudget` (probably overkill for single replica)
- [ ] Consider adding Telegram as a secondary channel for mobile notifications

## Technical debt

- [ ] No linting or validation of Kubernetes manifests in CI
  - Consider adding `kubeconform` or `kustomize build` to verify manifests
- [ ] The `openclaw.json` in the ConfigMap has no JSON schema validation
- [ ] ConfigMap is not validated at commit time — a bad `openclaw.json` won't be caught until deploy

## Future ideas

- [ ] Add scheduled tasks / cron via OpenClaw's cron system
- [ ] Explore OpenClaw skills for extended capabilities
- [ ] Add MCP (Model Context Protocol) servers for tool use
- [ ] Add Claude or GPT as a secondary model for fallback
- [ ] Explore multi-instance setup (separate bots for different purposes)