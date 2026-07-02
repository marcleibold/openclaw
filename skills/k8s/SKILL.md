---
name: k8s
description: Use the k8s toolset (k8s_list, k8s_get, k8s_logs, k8s_apply, k8s_delete) to investigate and manage Marc's self-hosted k3s cluster. Load this skill when the user asks about pods, deployments, services, RBAC, cluster state, or anything else k8s-flavored.
---

# Kubernetes operations

You have a typed `k8s` toolset wired to the pod's ServiceAccount token. The ServiceAccount (`wren` in the `ai-agent` namespace) has two grants:

1. **ClusterRole `wren-readonly`** — `get`/`list`/`watch` on pods, services, configmaps, secrets, pvc, events, namespaces, nodes, serviceaccounts across the whole cluster, plus `apps/*`, `batch/*`, and `networking.k8s.io/ingresses` read.
2. **Role `wren-self-manage`** in `ai-agent` — full CRUD on its own namespace (pods, configmaps, secrets, services, pvc, deployments, statefulsets, jobs, cronjobs).

So: read anything anywhere, write only inside `ai-agent`. Attempts to write elsewhere return a `Forbidden` error from the API server — surface that to the user, don't try workarounds.

## Tool catalogue

| Tool | When | Notes |
|---|---|---|
| `k8s_list(kind, namespace?, label_selector?)` | "What's running?" / "What's broken?" | Returns compact summary. Cluster-wide if no namespace. |
| `k8s_get(kind, name, namespace?)` | Full spec+status of one resource | Returns the YAML-shaped dict. |
| `k8s_logs(name, namespace, tail?, container?)` | Pod logs | Read-only. `tail` default 200, max 10000. |
| `k8s_apply(manifest, namespace?)` | Write a manifest | Subject to SA RBAC. For one-off dev / self-management, NOT production. |
| `k8s_delete(kind, name, namespace)` | Delete a resource | Subject to SA RBAC. |

`k8s_apply` and `k8s_delete` will return the API server's error verbatim on `Forbidden` — show the user the actual `User "system:serviceaccount:ai-agent:wren" cannot ...` line so the RBAC is auditable.

## Cluster shape (k3s, 3 nodes)

- **hp-elitedesk** — control-plane, Ubuntu 24.04
- **c-nuc7** — Ubuntu 24.04.4 LTS
- **rpi3**

Apps worth knowing: matrix (Synapse), postgres, mongodb, mosquitto, pihole, homeassistant, esphome, your-spotify, zigbee2mqtt, bezel, ai-agent, argo-cd, sealed-secrets, ingress-nginx, cert-manager, metallb, trivy, akri, nfs-provisioner, container-registry.

Storage class `local-path` (default). Sealed Secrets (bitnami) for secret management — cert lives in the `sealed-secrets` namespace. ArgoCD owns GitOps for the cluster.

## Troubleshooting playbooks

When the user reports an issue, walk the playbook top-down and stop as soon as you have an answer. Don't run all steps blindly.

### "Why is this pod failing?"

1. `k8s_list(kind="pods", namespace="<ns>")` — find the pod, check `phase` and `ready != N/N`.
2. `k8s_get(kind="pods", name=..., namespace=...)` — look at `status.conditions` and `status.containerStatuses[*].state.waiting.reason`. The single-line `reason` (e.g. `CrashLoopBackOff`, `ImagePullBackOff`, `CreateContainerConfigError`, `ErrImagePull`) tells you which playbook below applies.
3. `k8s_logs(name=..., namespace=..., tail=200)` — last 200 lines. Look for stack traces, missing files, connection refused, OOMKilled.
4. `k8s_list(kind="events", namespace="<ns>")` — recent events sorted by time. Look for `Warning` events: `Failed`, `BackOff`, `Unhealthy`, `FailedMount`.
5. **Only after diagnosis**: `k8s_delete(kind="pods", name=..., namespace=...)` to restart it (the ReplicaSet/Deployment will recreate).

### CrashLoopBackOff

The container is starting then dying. Cause is in the logs:

- `OOMKilled` in `lastState.terminated.reason` — increase memory limit, or fix the leak.
- Python `ImportError` / `ModuleNotFoundError` — the image is missing a dep. Rebuild with the new dep.
- Connection refused on a sidecar (e.g. postgres) — wait for the dependency to be ready, or fix the `depends_on` ordering.
- `configmap not found` / `secret not found` — the volume mount references something that doesn't exist.

Always quote the actual error from `k8s_logs` — don't paraphrase. If you can't tell from the logs, say so and stop.

### ImagePullBackOff / ErrImagePull

The kubelet can't fetch the image. Causes:

- Wrong image name / tag — `k8s_get(kind="pods", ...)` → `spec.containers[*].image`.
- Private registry without imagePullSecrets — needs `imagePullSecrets` on the PodSpec or ServiceAccount.
- Registry auth expired — `k8s_get(kind="secrets", name="<registry-creds>", namespace=...)` to see if it still exists, but you cannot decode it without `data` field access (you can).
- Tag was deleted from the registry (CI rebuilt with the same tag) — re-tag or roll the Deployment to a new image SHA.

### CreateContainerConfigError

The kubelet can't assemble the container spec. Most common: a referenced ConfigMap or Secret is missing. `k8s_list(kind="configmaps"/"secrets", namespace="<ns>")` to check what's there.

### Pending (not starting at all)

The pod is schedulable but not yet running. Causes:

- Insufficient CPU/memory on candidate nodes — `k8s_list(kind="pods", ...)` then look at the pod's `status.conditions[type=PodScheduled].message`.
- PVC not bound — `k8s_list(kind="persistentvolumeclaims", namespace="<ns>")` to check `phase`. If `Pending`, the storage class isn't provisioning (CSI driver issue, or no node with the disk).
- `local-path` PVCs are node-bound — a PVC provisioned on `hp-elitedesk` will only schedule pods there.

### 0/N ready on a Deployment

1. `k8s_list(kind="pods", namespace="<ns>", label_selector="<deployment selector>")` to find the pods.
2. For each pod, run the "Why is this pod failing?" playbook above.
3. If all pods are healthy but `ready_replicas < replicas`, check the Deployment's `status.conditions` — usually a `ProgressDeadlineExceeded` after a failed rollout.

### Service has no endpoints

1. `k8s_get(kind="endpoints", name="<svc>", namespace="<ns>")` — `subsets[].addresses` should list the matching pods. If empty, no pod matches the Service's selector.
2. Check the Service's selector matches the pod labels: `k8s_get(kind="services", name=..., namespace=...)` → `spec.selector`, vs `k8s_list(kind="pods", namespace=..., label_selector="<svc.selector>")`.

### Node NotReady

1. `k8s_list(kind="nodes")` — find the node, check `ready` field.
2. `k8s_get(kind="nodes", name=...)` → `status.conditions` for `Ready=False` reasons (`KubeletNotReady`, `NetworkUnavailable`, `DiskPressure`).
3. The user must SSH to the node to fix it — you can't from in-cluster. Tell them the specific condition and stop.

### RBAC / Forbidden

The user wants to do X, you try, API returns `Forbidden`. Steps:

1. Quote the error verbatim — it tells you the exact verb and resource denied.
2. Identify which Role/ClusterRole would need to grant it. If it's in `ai-agent`, edit `resources/rbac.yaml` and add the rule to `wren-self-manage`. If it's anywhere else, you need a new Role + RoleBinding. **Don't** suggest giving `wren` cluster-admin.
3. If it's a `pods/exec` request — refuse. That's a prompt-injection vector, not a feature. The user can `kubectl exec` from their own machine.

## Common workflows

### "Restart the X pod"

Single call: `k8s_delete(kind="pods", name="<x>", namespace="<ns>")`. The ReplicaSet/Deployment recreates it within seconds. Don't roll the whole Deployment.

### "Show me everything in namespace Y"

1. `k8s_list(kind="pods", namespace="<y>")` — sorted by `restarts` desc usually reveals the noisy ones.
2. If anything's unhealthy, `k8s_logs(...)` on it.
3. `k8s_list(kind="events", namespace="<y>")` for recent Warnings.

### "Is the cluster healthy?"

1. `k8s_list(kind="nodes")` — all 3 should have `ready=True`.
2. `k8s_list(kind="pods", namespace="kube-system")` — coredns, local-path-provisioner, metrics-server should all be Running.
3. `k8s_list(kind="pods", namespace="argo-cd")` — repo-server, application-controller should be Running.
4. `k8s_list(kind="pods", namespace="ingress-nginx")` — the controller should be Running on at least one node.

If any are degraded, drill in with `k8s_get` and `k8s_logs`.

## Output style

- Lead with the answer. If a pod is failing, say "X is in CrashLoopBackOff because <reason from logs>" in the first line, then show the supporting evidence.
- Use compact summaries from `k8s_list`. Don't paste the full YAML from `k8s_get` unless the user asked or the relevant info is in a deep field.
- Quote error messages verbatim — never paraphrase a `Forbidden` as "permission issue".
- When you make a write, show what you did and let the user decide whether to keep it.

## Anti-patterns

- **Don't `k8s_apply` production manifests directly.** Edit the Git repo, commit, push, let ArgoCD sync. The `k8s_apply` tool is for one-off dev work and self-management in `ai-agent`.
- **Don't use the `terminal` tool to run `kubectl`** when `k8s_*` would do — the typed tool gives structured output and Tirith may block shell-typed kubectl.
- **Don't escalate to cluster-admin by asking the user to "just add a binding".** If RBAC is blocking, surface the exact error and propose the minimal role change.
- **Don't try `pods/exec`.** It's intentionally denied. The user can SSH to the node or use their own kubeconfig.
- **Don't bulk-delete pods to "fix" a deployment.** If multiple pods are failing, the cause is the image or the config, not the pods.
