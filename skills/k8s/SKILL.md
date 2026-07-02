---
name: k8s
description: Use the k8s toolset (k8s_list, k8s_get, k8s_logs, k8s_apply, k8s_delete) to investigate and manage Marc's self-hosted k3s cluster. Load this skill when the user asks about pods, deployments, services, RBAC, cluster state, or anything else k8s-flavored.
---

# Kubernetes operations

You have a typed `k8s` toolset wired to the pod's ServiceAccount token. The ServiceAccount (`wren` in the `ai-agent` namespace) has two grants:

1. **ClusterRole `wren-readonly`** — `get`/`list`/`watch` on pods, services, configmaps, secrets, pvc, events, namespaces, nodes, serviceaccounts across the whole cluster, plus `apps/*`, `batch/*`, and `networking.k8s.io/ingresses` read.
2. **Role `wren-self-manage`** in `ai-agent` — full CRUD on its own namespace (pods, configmaps, secrets, services, pvc, deployments, statefulsets, jobs, cronjobs).

So: read anything anywhere, write only inside `ai-agent`. Attempts to write elsewhere return a `Forbidden` error from the API server — surface that to the user, don't try workarounds.

## When to use which tool

- **"What's broken?"** — `k8s_list(kind="pods", namespace="<x>")`, sort by `restarts` and `ready != N/N`. Then `k8s_logs(name=..., namespace=..., tail=200)`.
- **CrashLoopBackOff / ImagePullBackOff** — `k8s_get(kind="pods", ...)` for the full status, then `k8s_get(kind="events", ...)` to see why the kubelet is unhappy.
- **Describe a deployment** — `k8s_get(kind="deployments", name=..., namespace=...)` returns the full spec + status.
- **Restart a pod** — `k8s_delete(kind="pods", name=..., namespace=...)`. The ReplicaSet/Deployment will recreate it.
- **Apply a manifest** — `k8s_apply(manifest="...")`. Prefer putting the manifest in the repo and applying via GitOps (ArgoCD) for production. Use `k8s_apply` only for one-off dev work and self-management.
- **Read a Secret** — `k8s_get(kind="secrets", name=..., namespace=...)` returns the data field base64-encoded. Decoding for the user is fine; *writing* secrets to the public repo is not.

## Conventions for this cluster

- 3 nodes: `hp-elitedesk` (control-plane, Ubuntu 24.04), `c-nuc7` (Ubuntu 24.04.4 LTS), `rpi3`.
- Local-path storage class is the default; no cloud provider.
- Sealed Secrets (bitnami) for all secret management. Cert is in the `sealed-secrets` namespace.
- ArgoCD owns GitOps for the cluster. Changes to `SP0Fs/cluster` propagate automatically.
- `MARCSHELL` is the in-cluster postgres (not in the registry yet, so don't assume it's there).

## Output style

- Show `name`, `namespace`, and the most relevant status field (`phase`, `ready`, `restarts`). Don't dump full YAML unless the user asks.
- When a query returns > 20 items, summarize by phase / state and offer to drill in.
- Errors: quote the API server's message verbatim. Don't paraphrase a `Forbidden` as "permission issue" — show the actual `User "system:serviceaccount:ai-agent:wren" cannot ...` line so the user can audit.

## Anti-patterns

- **Don't `k8s_apply` production manifests directly.** Edit the Git repo, commit, push, let ArgoCD sync.
- **Don't use the `terminal` tool to run `kubectl`** when `k8s_*` would do — the typed tool gives structured output and Tirith may block shell-typed kubectl.
- **Don't escalate to cluster-admin by asking the user to "just add a binding".** If RBAC is blocking, surface the exact error and stop.
