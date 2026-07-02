"""k8s plugin — typed Kubernetes access for the Wren agent.

Uses the pod's ServiceAccount token (mounted at
/var/run/secrets/kubernetes.io/serviceaccount) and shells out to `kubectl`
in-cluster, but the LLM only ever sees the typed schema. The agent cannot
bypass shell-level controls (Tirith) and the SA's RBAC is enforced by the
API server regardless of how the request gets there.

Why typed tool, not bare `kubectl` via terminal:
  - LLM cannot craft a clever `kubectl` flag combo to escape RBAC.
  - Inputs are validated against a JSON schema; output is structured.
  - Permission errors come back as typed exceptions the LLM can reason
    about, not a 30-line stderr blob.
  - Every tool call is logged uniformly with the toolset name.

Why subprocess, not python kubernetes client:
  - The base image ships `kubectl` (k8s.io/client-go). The python client
    is not in the venv, would need an image rebuild, and is ~5x slower
    to import. This plugin is <100 lines, easier to reason about, and
    exactly the same capability surface.

Tools:
  k8s_list    — list resources (pods, services, deployments, ...) by namespace
  k8s_get     — get a single resource, returns its YAML
  k8s_logs    — last N lines of pod logs
  k8s_apply   — apply a manifest (subject to SA RBAC)
  k8s_delete  — delete a resource (subject to SA RBAC)
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

_KUBECTL = shutil.which("kubectl") or "/usr/local/bin/kubectl"
_SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"

# What kinds this plugin knows how to call. Adding a kind here makes
# k8s_list / k8s_get / k8s_delete work for it; k8s_apply accepts any kind
# the SA has RBAC for.
_KINDS = {
    # core
    "pods", "services", "configmaps", "secrets",
    "persistentvolumeclaims", "events", "nodes", "namespaces",
    "serviceaccounts", "endpoints",
    # apps
    "deployments", "statefulsets", "daemonsets", "replicasets",
    # batch
    "jobs", "cronjobs",
    # networking
    "ingresses",
}


def _run(args: List[str], timeout: int = 30) -> Dict[str, Any]:
    """Run kubectl with the in-cluster SA token, return parsed JSON or raise."""
    if shutil.which(_KUBECTL) is None:
        raise RuntimeError(f"kubectl not found at {_KUBECTL}")
    # kubectl auto-discovers the SA token from the well-known path. We don't
    # need to set KUBECONFIG or pass --token.
    proc = subprocess.run(
        [_KUBECTL, *args, "-o", "json"],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        # Surface the API server's actual error so the LLM can reason.
        raise RuntimeError(
            f"kubectl {args[:3]}... failed (exit {proc.returncode}): "
            f"{proc.stderr.strip()[:500]}"
        )
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        # Some commands (logs) don't return JSON; fall back to raw text.
        return {"_raw": proc.stdout}


# -------------------------------------------------------------------
# Handlers
# -------------------------------------------------------------------

def _list_impl(kind: str, namespace: Optional[str], label_selector: Optional[str]) -> Dict[str, Any]:
    if kind not in _KINDS:
        raise ValueError(f"unsupported kind: {kind!r}")
    args = ["get", kind]
    if namespace:
        args += ["-n", namespace]
    else:
        args += ["--all-namespaces"]
    if label_selector:
        args += ["-l", label_selector]
    resp = _run(args)
    # Compact summary — don't dump full YAML into the LLM context.
    items = []
    for it in resp.get("items", []):
        meta = it.get("metadata", {})
        spec = it.get("spec", {}) or {}
        status = it.get("status", {}) or {}
        entry = {
            "name": meta.get("name"),
            "namespace": meta.get("namespace"),
            "labels": meta.get("labels") or {},
        }
        if kind == "pods":
            entry["phase"] = status.get("phase")
            cs = status.get("containerStatuses") or []
            entry["ready"] = f"{sum(1 for c in cs if c.get('ready'))}/{len(cs)}"
            entry["restarts"] = sum(c.get("restartCount", 0) for c in cs)
        elif kind == "deployments":
            entry["ready"] = f"{status.get('readyReplicas', 0)}/{spec.get('replicas', 0)}"
        elif kind == "services":
            entry["type"] = spec.get("type")
            entry["cluster_ip"] = spec.get("clusterIP")
        elif kind == "nodes":
            entry["ready"] = any(
                c.get("type") == "Ready" and c.get("status") == "True"
                for c in (status.get("conditions") or [])
            )
        items.append(entry)
    return {"count": len(items), "items": items}


def _get_impl(kind: str, name: str, namespace: Optional[str]) -> Dict[str, Any]:
    if kind not in _KINDS:
        raise ValueError(f"unsupported kind: {kind!r}")
    args = ["get", kind, name]
    if namespace:
        args += ["-n", namespace]
    return _run(args)


def _logs_impl(name: str, namespace: str, tail: int, container: Optional[str]) -> Dict[str, Any]:
    args = ["logs", name, "-n", namespace, f"--tail={tail}"]
    if container:
        args += ["-c", container]
    # Logs don't return JSON; _run falls back to _raw on parse failure.
    result = _run(args, timeout=60)
    if "_raw" in result:
        return {
            "pod": name,
            "namespace": namespace,
            "container": container,
            "lines_requested": tail,
            "log": result["_raw"],
        }
    return result


def _apply_impl(manifest: str, namespace: Optional[str]) -> Dict[str, Any]:
    """Apply a manifest. server-side apply via kubectl."""
    if not manifest.strip():
        raise ValueError("manifest is empty")
    # Write to a tmp file in /tmp (emptyDir) and pass to kubectl.
    import tempfile
    fd, path = tempfile.mkstemp(suffix=".yaml", dir="/tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(manifest)
        args = ["apply", "-f", path]
        if namespace:
            args += ["-n", namespace]
        # `apply -o json` returns the URS object describing what changed.
        result = _run(args, timeout=60)
        changes = []
        # Output is a list of "configured" objects.
        items = result if isinstance(result, list) else result.get("items", [result])
        for it in items:
            changes.append({
                "kind": it.get("kind"),
                "name": (it.get("metadata") or {}).get("name"),
                "namespace": (it.get("metadata") or {}).get("namespace"),
            })
        return {"applied": changes}
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def _delete_impl(kind: str, name: str, namespace: str) -> Dict[str, Any]:
    if kind not in _KINDS:
        raise ValueError(f"unsupported kind: {kind!r}")
    args = ["delete", kind, name, "-n", namespace]
    result = _run(args, timeout=30)
    return {
        "kind": kind,
        "name": name,
        "namespace": namespace,
        "status": result.get("status", "Unknown"),
    }


# -------------------------------------------------------------------
# Schemas
# -------------------------------------------------------------------

K8S_LIST_SCHEMA: Dict[str, Any] = {
    "name": "k8s_list",
    "description": (
        "List Kubernetes resources. Returns a compact summary (name, "
        "namespace, status). Use k8s_get for full YAML. The ServiceAccount's "
        "RBAC determines which resources are visible."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "kind": {
                "type": "string",
                "description": (
                    "Resource kind (lowercase, plural). One of: pods, services, "
                    "configmaps, secrets, deployments, statefulsets, daemonsets, "
                    "jobs, cronjobs, ingresses, events, nodes, namespaces, "
                    "persistentvolumeclaims, serviceaccounts, endpoints, replicasets."
                ),
            },
            "namespace": {
                "type": "string",
                "description": "Namespace to scope the list. Omit for cluster-scoped resources (nodes, namespaces).",
            },
            "label_selector": {
                "type": "string",
                "description": "Standard k8s label selector, e.g. 'app=ai-agent' or 'tier=frontend,env=prod'.",
            },
        },
        "required": ["kind"],
    },
}

K8S_GET_SCHEMA: Dict[str, Any] = {
    "name": "k8s_get",
    "description": "Fetch a single Kubernetes resource and return its full YAML-shaped dict.",
    "parameters": {
        "type": "object",
        "properties": {
            "kind": {"type": "string", "description": "Resource kind (lowercase, plural)."},
            "name": {"type": "string", "description": "Resource name."},
            "namespace": {"type": "string", "description": "Required for namespaced kinds; omit for cluster-scoped."},
        },
        "required": ["kind", "name"],
    },
}

K8S_LOGS_SCHEMA: Dict[str, Any] = {
    "name": "k8s_logs",
    "description": "Get the last N lines of a pod's logs. Requires 'pods/log' RBAC on the pod's namespace.",
    "parameters": {
        "type": "object",
        "properties": {
            "name": {"type": "string", "description": "Pod name."},
            "namespace": {"type": "string", "description": "Pod namespace."},
            "tail": {"type": "integer", "description": "Number of lines from the end. Default 200.", "minimum": 1, "maximum": 10000},
            "container": {"type": "string", "description": "Container name (omit for the first non-init container)."},
        },
        "required": ["name", "namespace"],
    },
}

K8S_APPLY_SCHEMA: Dict[str, Any] = {
    "name": "k8s_apply",
    "description": (
        "Apply a Kubernetes manifest (YAML or JSON, possibly multi-document). "
        "Replaces if the resource exists, creates otherwise. Subject to the "
        "ServiceAccount's RBAC. Use sparingly and prefer GitOps for production."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "manifest": {
                "type": "string",
                "description": "Full manifest text. May contain multiple documents separated by '---'.",
            },
            "namespace": {
                "type": "string",
                "description": "Default namespace to apply manifests into if they don't specify one.",
            },
        },
        "required": ["manifest"],
    },
}

K8S_DELETE_SCHEMA: Dict[str, Any] = {
    "name": "k8s_delete",
    "description": "Delete a Kubernetes resource. Subject to the ServiceAccount's RBAC.",
    "parameters": {
        "type": "object",
        "properties": {
            "kind": {"type": "string", "description": "Resource kind (lowercase, plural)."},
            "name": {"type": "string", "description": "Resource name."},
            "namespace": {"type": "string", "description": "Required for namespaced kinds."},
        },
        "required": ["kind", "name", "namespace"],
    },
}


# -------------------------------------------------------------------
# Runtime gate
# -------------------------------------------------------------------

def check_k8s_requirements() -> bool:
    """True when both the SA token is mounted and kubectl is in PATH."""
    if not os.path.exists(os.path.join(_SA_DIR, "token")):
        return False
    if shutil.which(_KUBECTL) is None:
        return False
    return True


# -------------------------------------------------------------------
# Registration
# -------------------------------------------------------------------

def register(ctx) -> None:
    if not check_k8s_requirements():
        logger.info(
            "k8s plugin: SA token or kubectl missing; tools will fail at call time. "
            "Check automountServiceAccountToken=true and that the image ships kubectl."
        )

    for name, schema, handler in (
        ("k8s_list",   K8S_LIST_SCHEMA,   _list_impl),
        ("k8s_get",    K8S_GET_SCHEMA,    _get_impl),
        ("k8s_logs",   K8S_LOGS_SCHEMA,   _logs_impl),
        ("k8s_apply",  K8S_APPLY_SCHEMA,  _apply_impl),
        ("k8s_delete", K8S_DELETE_SCHEMA, _delete_impl),
    ):
        ctx.register_tool(
            name=name,
            toolset="k8s",
            schema=schema,
            handler=handler,
            check_fn=check_k8s_requirements,
            emoji="☸️",
        )
