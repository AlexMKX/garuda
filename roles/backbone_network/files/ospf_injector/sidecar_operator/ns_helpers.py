"""Linux namespace helpers used by the sidecar_operator docker_api module.

Extracted from docker_api.py to keep that module focused on Docker SDK
container lifecycle operations. These helpers read Linux procfs directly
and are independent of the Docker SDK client.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from docker.errors import NotFound  # type: ignore[import-untyped]

if TYPE_CHECKING:
    from docker import DockerClient

from sidecar_operator.exceptions import DockerUnavailableError

logger = logging.getLogger(__name__)

TRANSIENT_NS_INODE: str = ""
"""Sentinel value for an unresolvable namespace inode (transient PID race)."""


@dataclass(frozen=True)
class ContainerNamespaceInodes:
    """Effective Linux namespace inode identities for a running container.

    Each field holds the result of ``os.readlink(/proc/<pid>/ns/<kind>)``,
    e.g. ``"net:[4026531992]"``.  An empty string means the inode could not
    be resolved due to a transient restart race (PID is zero, the container
    disappeared between inspect and procfs read, or the procfs entry is
    absent).  Empty fields must be treated as *unknown* — not as a namespace
    mismatch — by callers.

    Attributes:
        net: network namespace inode string, or empty string if unresolvable.
        pid: PID namespace inode string, or empty string if unresolvable.
        ipc: IPC namespace inode string, or empty string if unresolvable.
    """

    net: str
    pid: str
    ipc: str


def read_container_ns_inodes(
    docker: "DockerClient",
    container_id: str,
) -> ContainerNamespaceInodes:
    """Read effective Linux namespace inode strings for a container.

    Inspects the container via the Docker API to obtain its host PID, then
    reads ``/proc/<pid>/ns/{net,pid,ipc}`` symlinks to determine the actual
    namespace identity for each kind.

    Transient restart races (container not found, PID is zero, or the procfs
    namespace entry has vanished between inspect and read) are surfaced as
    empty strings in the returned ``ContainerNamespaceInodes``.  Callers must
    treat empty strings as *unknown* and defer drift decisions to the next
    reconcile pass rather than treating them as mismatches.

    Args:
        docker: Docker SDK client.
        container_id: full or short Docker container ID.

    Returns:
        ``ContainerNamespaceInodes`` with each field set to the symlink target
        (e.g. ``"net:[4026531992]"``) or ``TRANSIENT_NS_INODE`` (empty string)
        when the inode is temporarily unresolvable.

    Raises:
        DockerUnavailableError: when the Docker API returns a communication or
            API-level error (``docker.errors.APIError``,
            ``docker.errors.DockerException``).  Container-not-found and procfs
            races are handled locally and **not** re-raised.
        PermissionError: if ``/proc/<pid>/ns/*`` cannot be read due to
            insufficient OS permissions.  The caller must handle this as a
            per-container skip, not a global abort.
    """
    import docker as _docker_module  # type: ignore[import-untyped]

    _empty = ContainerNamespaceInodes(
        net=TRANSIENT_NS_INODE,
        pid=TRANSIENT_NS_INODE,
        ipc=TRANSIENT_NS_INODE,
    )

    try:
        container = docker.containers.get(container_id)
    except NotFound:
        logger.debug(
            "container %s not found during ns inode read; treating as transient",
            container_id,
        )
        return _empty
    except (
        _docker_module.errors.APIError,
        _docker_module.errors.DockerException,
    ) as exc:
        raise DockerUnavailableError(
            f"failed to inspect container {container_id} for ns inodes: {exc}"
        ) from exc

    host_pid = _extract_container_pid(container.attrs)
    if host_pid <= 0:
        logger.debug(
            "container %s has pid=0; treating ns inodes as transient",
            container_id,
        )
        return _empty

    net_inode = _read_ns_symlink(host_pid, "net")
    pid_inode = _read_ns_symlink(host_pid, "pid")
    ipc_inode = _read_ns_symlink(host_pid, "ipc")

    return ContainerNamespaceInodes(net=net_inode, pid=pid_inode, ipc=ipc_inode)


def _extract_container_pid(container_attrs: dict[str, Any]) -> int:
    """Extract PID from Docker container attrs, defaulting to zero when missing."""
    state = container_attrs.get("State")
    if not isinstance(state, dict):
        return 0
    pid_raw = state.get("Pid")
    try:
        return int(pid_raw)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return 0


def _read_ns_symlink(host_pid: int, ns_kind: str) -> str:
    """Read a single ``/proc/<pid>/ns/<kind>`` symlink.

    Args:
        host_pid: host PID of the container process (from Docker inspect).
        ns_kind: namespace kind string — one of ``"net"``, ``"pid"``, ``"ipc"``.

    Returns:
        The symlink target (e.g. ``"net:[4026531992]"``) or
        ``TRANSIENT_NS_INODE`` (empty string) when the entry has vanished
        (race between PID read and procfs access).

    Raises:
        PermissionError: propagated unchanged so callers can distinguish
            a configuration/privilege problem from a transient race.
    """
    path = f"/proc/{host_pid}/ns/{ns_kind}"
    try:
        return os.readlink(path)
    except FileNotFoundError:
        logger.debug("procfs entry %s vanished; treating as transient", path)
        return TRANSIENT_NS_INODE
