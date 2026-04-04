# TODO

Open tasks and technical debt, roughly ordered by priority.

## Blockers (must do before first deployment)

- [x] Create Matrix account `@nanobot:matrix.leibold.tech` on Synapse
- [x] Obtain Matrix access token and device ID for the nanobot account
- [x] Obtain a MiniMax API key and re-seal `resources/secret.yaml`
- [x] Create `config.json` and seal it as `resources/secret.yaml`
- [ ] Trigger first Docker image build (push Dockerfile to master, or manual dispatch)
- [ ] Verify GHCR image pull works from the cluster (may need imagePullSecret for private packages)

## Post-deployment validation

- [ ] Verify `/health` endpoint accuracy — does it reflect Matrix channel connectivity?
- [ ] Verify E2EE works end-to-end (send encrypted message, confirm nanobot decrypts and responds)
- [ ] Verify PVC data persists across pod restarts (kill pod, check Matrix sync resumes)
- [ ] Verify memory/conversation history persists across restarts
- [ ] Load-test resource limits — are 1 CPU / 1Gi memory sufficient for typical use?

## Improvements

- [ ] Pin Docker image to SHA tag instead of `latest` in deployment.yaml
- [ ] Add imagePullSecret if GHCR package is private
- [ ] Add `nodeSelector` to exclude rpi3 (arm) if image is amd64-only
- [ ] Consider adding `podDisruptionBudget` (probably overkill for single replica)
- [ ] Add Prometheus metrics scraping if nanobot exposes metrics
- [ ] Add network policy to restrict egress to only matrix.leibold.tech and LLM provider domains

## Technical debt

- [ ] Dockerfile clones entire upstream repo — could use a lighter approach (pip install from PyPI)
- [ ] Config is fully opaque in git due to SealedSecret — no visibility into non-sensitive settings
  - Consider splitting into ConfigMap (non-sensitive) + Secret (sensitive) with an init container to merge
- [ ] No automated version bumping for upstream NanoBot releases
  - Consider Dependabot or Renovate for the `NANOBOT_VERSION` build arg
- [ ] No linting or validation of Kubernetes manifests in CI
  - Consider adding `kubeval`, `kubeconform`, or `kustomize build` to the workflow
- [ ] GitHub Actions workflow only triggers on Dockerfile changes — should also trigger on version bumps or manual schedule

## Future ideas

- [ ] Add Telegram as a secondary channel (for mobile notifications when Matrix is unavailable)
- [ ] Add scheduled tasks / cron reminders via nanobot's built-in cron support
- [ ] Integrate with Home Assistant via nanobot skills
- [ ] Add MCP (Model Context Protocol) servers for tool use
- [ ] Explore multi-instance setup (separate bots for different purposes)
