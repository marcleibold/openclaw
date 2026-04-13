# TODO

Open tasks and technical debt, roughly ordered by priority.

## Initial deployment

- [ ] Create `openclaw` namespace and apply ArgoCD app: `kubectl apply -f application.yaml -n argo-cd`
- [ ] Generate and seal `openclaw-secrets` Secret with your API keys
- [ ] Configure Matrix channel in `openclaw.json` (add homeserver, accessToken)
- [ ] Verify Control UI is accessible at http://localhost:18789 with gateway token
- [ ] Verify Matrix connection — bot joins and responds to DMs
- [ ] Re-verify Matrix E2EE devices in Element client (E2EE state is fresh on first deploy)

## Post-deployment verification

- [ ] Verify Matrix E2EE works (encrypted DM, verify device in Element)
- [ ] Verify PVC data persists across pod restarts (Matrix sync resumes)
- [ ] Verify memory/conversation history persists across restarts
- [ ] Verify Control UI shows correct status and chat history

## Improvements

- [ ] Pin image to SHA tag instead of `latest` in deployment.yaml
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