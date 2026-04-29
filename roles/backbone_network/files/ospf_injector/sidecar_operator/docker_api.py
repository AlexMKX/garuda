"""Docker SDK helper functions for the generic sidecar operator.

Provides thin helpers that translate between the operator's domain models and
the Docker SDK API. All functions accept and return Docker SDK objects directly
at boundaries where containers are needed — no wrapper classes are used.

Functions:
- list_containers: list all containers and normalize into ContainerInfo models.
- list_managed_sidecars: discover managed sidecar containers by label and scope.
- list_workload_interfaces: return interface names visible in a target container's netns.
- read_container_ns_inodes: read effective namespace inode strings for a container.
- build_create_kwargs: translate DesiredSidecarSpec into docker SDK create kwargs.
- create_sidecar: create and start a sidecar container from a DesiredSidecarSpec.
- remove_sidecar: stop and remove a managed sidecar container.
"""

from __future__ import annotations

import json
import logging
import subprocess
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from docker.errors import NotFound  # type: ignore[import-untyped]

if TYPE_CHECKING:
    from docker import DockerClient
    from docker.models.containers import Container

from sidecar_operator.models import ActualSidecarRef, ContainerInfo, DesiredSidecarSpec

from sidecar_operator.exceptions import DockerUnavailableError  # noqa: F401 — re-export
from sidecar_operator.ns_helpers import (  # noqa: F401 — re-exports for backward compat
    ContainerNamespaceInodes,
    TRANSIENT_NS_INODE,
    _extract_container_pid,
    _read_ns_symlink,
    read_container_ns_inodes,
)

logger = logging.getLogger(__name__)


# Label keys used to identify and index managed sidecars.
_LABEL_MANAGED_BY = "garuda.managed-by"
_LABEL_OPERATOR_SCOPE = "garuda.operator-scope"
_LABEL_SIDECAR_CONSUMER = "garuda.sidecar-consumer"
_LABEL_TARGET_CONTAINER = "garuda.target-container"
_LABEL_TARGET_CONTAINER_ID = "garuda.target-container-id"

_MANAGED_BY_VALUE = "sidecar-operator"

# Timeout for the nsenter invocation used by list_workload_interfaces.
# The target netns is local (same host) so this is effectively only
# protection against a hung subprocess.
_NSENTER_TIMEOUT_SECONDS = 5


def list_containers(docker: "DockerClient") -> list[ContainerInfo]:
    """List all containers and normalize into ContainerInfo models.

    Args:
        docker: a connected Docker SDK client.

    Returns:
        A list of ContainerInfo, one per container visible to the daemon.

    Raises:
        DockerUnavailableError: if the Docker API call fails.
    """
    try:
        raw_containers = docker.containers.list(all=True)
    except (
        Exception
    ) as exc:  # noqa: BLE001 — re-raises as DockerUnavailableError; boundary catch
        raise DockerUnavailableError(f"failed to list containers: {exc}") from exc

    result: list[ContainerInfo] = []

    for c in raw_containers:
        networks: dict[str, str] = {}
        net_settings = c.attrs.get("NetworkSettings", {}).get("Networks", {})
        for net_name, net_data in net_settings.items():
            ip = net_data.get("IPAddress", "")
            networks[net_name] = ip

        host_config = c.attrs.get("HostConfig", {})
        network_mode = host_config.get("NetworkMode", "")

        result.append(
            ContainerInfo(
                name=c.name,
                id=str(c.attrs.get("Id") or c.id),
                state=c.status,
                networks=networks,
                labels=c.labels or {},
                network_mode=network_mode,
            )
        )

    return result


def list_managed_sidecars(
    docker: "DockerClient",
    operator_scope: str,
) -> list[ActualSidecarRef]:
    """Discover all managed sidecar containers for the given operator scope.

    Queries Docker for all containers carrying the managed-by label, then
    filters to those matching the given operator_scope. Extracts ActualSidecarRef
    fields from container labels and HostConfig attrs.

    Label contract:
    - garuda.managed-by=sidecar-operator (required; filters unmanaged containers)
    - garuda.operator-scope=<operator_scope> (required; filters by scope)
    - garuda.sidecar-consumer -> consumer_name
    - garuda.target-container -> target_name
    - garuda.target-container-id -> target_container_id

    State and namespace mode values are extracted from container.attrs.

    Args:
        docker: Docker SDK client.
        operator_scope: the operator scope to filter by (e.g. "backbone_network").

    Returns:
        List of ActualSidecarRef instances for all managed sidecars in scope.
    """
    containers: list["Container"] = docker.containers.list(
        all=True, filters={"label": f"{_LABEL_MANAGED_BY}={_MANAGED_BY_VALUE}"}
    )
    results: list[ActualSidecarRef] = []

    for container in containers:
        labels: dict[str, str] = container.labels or {}

        # Defensive Python-side filter: in tests, mock clients ignore filters kwarg
        # and return whatever return_value is set to. These two checks ensure only
        # true managed sidecars with the correct scope pass through regardless.
        if labels.get(_LABEL_MANAGED_BY) != _MANAGED_BY_VALUE:
            continue
        if labels.get(_LABEL_OPERATOR_SCOPE) != operator_scope:
            continue

        # Strip leading '/' that Docker sometimes prepends to container names.
        sidecar_name = container.name.lstrip("/")

        state: str = container.attrs.get("State", {}).get("Status", "") or ""
        host_config: dict[str, Any] = container.attrs.get("HostConfig", {})
        network_mode: str = host_config.get("NetworkMode", "") or ""
        pid_mode: str = host_config.get("PidMode", "") or ""
        ipc_mode: str = host_config.get("IpcMode", "") or ""

        results.append(
            ActualSidecarRef(
                consumer_name=labels.get(_LABEL_SIDECAR_CONSUMER, ""),
                target_name=labels.get(_LABEL_TARGET_CONTAINER, ""),
                target_container_id=labels.get(_LABEL_TARGET_CONTAINER_ID, ""),
                sidecar_name=sidecar_name,
                sidecar_container_id=container.id,
                labels=labels,
                state=state,
                network_mode=network_mode,
                pid_mode=pid_mode,
                ipc_mode=ipc_mode,
            )
        )

    return results


def build_create_kwargs(desired: DesiredSidecarSpec) -> dict[str, Any]:
    """Translate a DesiredSidecarSpec into Docker SDK container create keyword arguments.

    Produces a dict suitable for passing to docker.containers.run() or
    docker.api.create_container(). The caller is responsible for passing these
    kwargs to the Docker SDK.

    SharedNamespaces fields map to Docker create kwargs as follows:
    - network=True  -> network_mode="container:<target_container_id>"
    - pid=True      -> pid_mode="container:<target_container_id>"
    - ipc=True      -> ipc_mode="container:<target_container_id>"

    Args:
        desired: the desired sidecar specification.

    Returns:
        A dict of keyword arguments for the Docker SDK container create call.
    """
    kwargs: dict[str, Any] = {
        "name": desired.sidecar_name,
        "image": desired.image,
        "environment": desired.environment,
        "labels": desired.labels,
        "cap_add": desired.capabilities,
        "restart_policy": {"Name": desired.restart_policy_name},
        "detach": True,
    }

    target_id = desired.target_container_id
    ns = desired.shared_namespaces

    if ns.network:
        kwargs["network_mode"] = f"container:{target_id}"
    if ns.pid:
        kwargs["pid_mode"] = f"container:{target_id}"
    if ns.ipc:
        kwargs["ipc_mode"] = f"container:{target_id}"

    return kwargs


def create_sidecar(
    docker: "DockerClient",
    desired: DesiredSidecarSpec,
) -> "Container":
    """Create and start a sidecar container from a DesiredSidecarSpec.

    Translates the spec into Docker SDK kwargs, creates the container, and
    starts it. Returns the Docker SDK Container object.

    Args:
        docker: Docker SDK client.
        desired: the desired sidecar specification.

    Returns:
        The newly created and started Docker SDK Container.
    """
    kwargs = build_create_kwargs(desired)
    logger.info(
        "creating sidecar %s (image=%s, consumer=%s, target=%s)",
        desired.sidecar_name,
        desired.image,
        desired.consumer_name,
        desired.target_name,
    )
    container: "Container" = docker.containers.run(**kwargs)
    return container


def remove_sidecar(
    docker: "DockerClient",
    actual: ActualSidecarRef,
) -> None:
    """Stop and remove a managed sidecar container.

    Looks up the container by its stored sidecar_container_id and removes it.
    If the container is not found (already gone), logs a warning and returns.

    Args:
        docker: Docker SDK client.
        actual: the actual sidecar reference identifying the container to remove.
    """
    logger.info(
        "removing sidecar %s (id=%s, consumer=%s, target=%s)",
        actual.sidecar_name,
        actual.sidecar_container_id,
        actual.consumer_name,
        actual.target_name,
    )
    try:
        container: "Container" = docker.containers.get(actual.sidecar_container_id)
        container.stop()
        container.remove()
    except NotFound:
        logger.warning(
            "sidecar %s (id=%s) not found during removal — already gone",
            actual.sidecar_name,
            actual.sidecar_container_id,
        )


def list_workload_interfaces(
    client: "DockerClient",
    container_id: str,
) -> set[str]:
    """Return interface names visible in a workload container's netns.

    Strategy: nsenter into the target container's network namespace from the
    operator side and run ``ip -j link show`` using the operator's own
    ``iproute2``. This deliberately avoids ``container.exec_run("ip ...")``
    because many target images (Firezone, BusyBox/Alpine-based) ship either
    no ``ip`` binary at all or a BusyBox applet that does not support
    ``-j/--json``. The operator container must run with ``pid: host`` and
    either ``privileged: true`` or ``CAP_SYS_ADMIN``; see the
    ``docker-compose.yml.j2`` template for the sidecar operator.

    Args:
        client: a connected Docker SDK client used to resolve the target PID.
        container_id: the target workload container id (short or long form).

    Returns:
        The set of interface names visible in the target's netns, including
        ``lo``. Callers (e.g. ``FRRConsumer.on_reconcile``) use this to
        validate that declared interfaces actually exist before rendering
        downstream config.

    Raises:
        DockerUnavailableError: on any failure — Docker inspect error, the
            target reporting ``State.Pid == 0`` (transient restart), a
            non-zero nsenter exit, unparseable JSON, or an empty result
            (every real netns has at least ``lo``).
    """
    try:
        container = client.containers.get(container_id)
        attrs = container.attrs
    except (
        Exception
    ) as exc:  # noqa: BLE001 — re-raises as DockerUnavailableError; boundary catch
        raise DockerUnavailableError(
            f"failed to inspect workload container {container_id}: {exc}"
        ) from exc

    host_pid = _extract_container_pid(attrs)
    if host_pid <= 0:
        # PID 0 means the container is restarting / exited / not yet running.
        # Surface this as DockerUnavailableError so the reconcile loop skips
        # the pair this tick instead of aborting the whole run.
        raise DockerUnavailableError(
            f"failed to inspect workload interfaces for {container_id}: "
            f"container has pid=0 (transient restart)"
        )

    cmd = ["nsenter", "-t", str(host_pid), "-n", "ip", "-j", "link", "show"]
    try:
        completed = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=_NSENTER_TIMEOUT_SECONDS,
            check=False,
        )
    except (
        Exception
    ) as exc:  # noqa: BLE001 — re-raises as DockerUnavailableError; boundary catch
        raise DockerUnavailableError(
            f"failed to run nsenter for workload {container_id} "
            f"(pid={host_pid}): {exc}"
        ) from exc

    if completed.returncode != 0:
        raise DockerUnavailableError(
            f"failed to inspect workload interfaces for {container_id}: "
            f"nsenter -t {host_pid} -n ip -j link show returned "
            f"{completed.returncode}: {completed.stderr.strip()}"
        )

    try:
        records = json.loads(completed.stdout)
    except (
        ValueError
    ) as exc:  # noqa: BLE001 — re-raises as DockerUnavailableError; boundary catch
        raise DockerUnavailableError(
            f"failed to parse 'ip -j link show' output for {container_id} "
            f"(pid={host_pid}): {exc}"
        ) from exc

    names: set[str] = set()
    for record in records:
        ifname = record.get("ifname") if isinstance(record, dict) else None
        if isinstance(ifname, str) and ifname:
            names.add(ifname)

    if not names:
        raise DockerUnavailableError(
            f"failed to inspect workload interfaces for {container_id}: "
            f"no interfaces parsed from 'ip -j link show' (pid={host_pid})"
        )

    return names
