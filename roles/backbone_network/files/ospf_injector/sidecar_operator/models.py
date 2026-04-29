"""Shared data models for the generic sidecar operator.

These models are consumer-agnostic. Consumers (ospf, pbr, etc.) populate
DesiredSidecarSpec to declare what they want; the discovery layer populates
ActualSidecarRef from Docker label queries.

The reconcile planner compares desired vs actual keyed by (consumer_name, target_name).

Classes:
- SharedNamespaces: declares which Linux namespaces the sidecar should share with
  the target container (network, pid, ipc).
- DesiredSidecarSpec: the full specification for one sidecar that a consumer wants
  to exist alongside a target container.
- ActualSidecarRef: the discovered state of a managed sidecar, populated from
  Docker container metadata and labels.
- SidecarStopContext: contextual metadata passed to the before_sidecar_stopped hook.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class ContainerInfo(BaseModel):
    """Normalized container metadata from Docker API.

    This is the input to the discovery layer. It is intentionally
    decoupled from the Docker SDK types so discovery can be tested
    without a live daemon.

    Attributes:
        name: container name (e.g. 'wg_tik-1')
        id: Docker container ID (full 64-hex value)
        state: container state string ('running', 'exited', etc.)
        networks: mapping of network-name -> IPv4 address string
        labels: container labels
        network_mode: Docker HostConfig.NetworkMode value
    """

    name: str
    id: str
    state: str
    networks: dict[str, str] = Field(default_factory=dict)
    labels: dict[str, str] = Field(default_factory=dict)
    network_mode: str = ""


class SharedNamespaces(BaseModel):
    """Linux namespace sharing configuration between sidecar and target container.

    Controls which Docker HostConfig namespace-mode fields are set to share the
    target container's namespace vs remain private to the sidecar.

    Attributes:
        network: share target's network namespace (network_mode=container:<id>).
        pid: share target's PID namespace (pid_mode=container:<id>).
        ipc: share target's IPC namespace (ipc_mode=container:<id>).
    """

    network: bool = True
    pid: bool = False
    ipc: bool = False


class DesiredSidecarSpec(BaseModel):
    """Full specification for a sidecar that a consumer wants alongside a target.

    The reconcile planner uses this to determine whether to create, replace,
    or leave alone the corresponding actual sidecar.

    Attributes:
        consumer_name: identifies the operator consumer (e.g. "ospf", "pbr").
            Together with target_name forms the unique join key.
        target_name: name of the target container this sidecar attaches to.
        target_container_id: current Docker container ID of the target.
            Used to detect binding drift after target restarts.
        sidecar_name: deterministic container name for the sidecar.
        image: Docker image to use when creating the sidecar.
        labels: labels to apply to the sidecar container. Any label present in
            desired but absent or different in actual is treated as drift.
        environment: environment variables for the sidecar container.
        shared_namespaces: which Linux namespaces to share with the target.
        capabilities: Linux capabilities to add to the sidecar container.
        restart_policy_name: Docker restart policy name (default: unless-stopped).
    """

    consumer_name: str
    target_name: str
    target_container_id: str
    sidecar_name: str
    image: str
    labels: dict[str, str]
    environment: dict[str, str] = Field(default_factory=dict)
    shared_namespaces: SharedNamespaces = Field(default_factory=SharedNamespaces)
    capabilities: list[str] = Field(default_factory=list)
    restart_policy_name: str = "unless-stopped"


class ActualSidecarRef(BaseModel):
    """Discovered state of a managed sidecar container.

    Populated from Docker container metadata and ownership labels by the
    discovery layer. Used by the reconcile planner to compare against the
    desired state.

    Attributes:
        consumer_name: consumer that owns this sidecar (from label or convention).
        target_name: name of the target container this sidecar is bound to.
        target_container_id: Docker container ID stored as the binding reference.
        sidecar_name: container name of the sidecar.
        sidecar_container_id: Docker container ID of the sidecar itself.
        labels: labels currently applied to the sidecar container.
        state: Docker container state string ('running', 'exited', 'created', etc.).
            Empty string means the state is unknown, which is treated as drift.
        network_mode: Docker HostConfig.NetworkMode value.
        pid_mode: Docker HostConfig.PidMode value.
        ipc_mode: Docker HostConfig.IpcMode value.
        target_netns_inode: effective network namespace inode of the target container,
            e.g. ``"net:[4026531992]"``. Empty string means unresolvable (transient).
        sidecar_netns_inode: effective network namespace inode of the sidecar container.
            Empty string means unresolvable (transient).
        target_pid_ns_inode: effective PID namespace inode of the target container.
            Empty string means unresolvable (transient).
        sidecar_pid_ns_inode: effective PID namespace inode of the sidecar container.
            Empty string means unresolvable (transient).
        target_ipc_ns_inode: effective IPC namespace inode of the target container.
            Empty string means unresolvable (transient).
        sidecar_ipc_ns_inode: effective IPC namespace inode of the sidecar container.
            Empty string means unresolvable (transient).
    """

    consumer_name: str
    target_name: str
    target_container_id: str
    sidecar_name: str
    sidecar_container_id: str
    labels: dict[str, str]
    state: str = ""
    network_mode: str = ""
    pid_mode: str = ""
    ipc_mode: str = ""
    target_netns_inode: str = ""
    sidecar_netns_inode: str = ""
    target_pid_ns_inode: str = ""
    sidecar_pid_ns_inode: str = ""
    target_ipc_ns_inode: str = ""
    sidecar_ipc_ns_inode: str = ""


class SidecarStopContext(BaseModel):
    """Contextual metadata passed to the before_sidecar_stopped consumer hook.

    Passed to consumers before every sidecar removal so they can perform
    advisory cleanup (e.g. drain routing state, flush rules). The hook is
    always advisory — the sidecar is removed unconditionally after it returns.

    Attributes:
        reason: why the sidecar is being stopped.
            - "orphaned": no matching target container found.
            - "target_died": target container exited or disappeared.
            - "target_no_longer_matches": target no longer satisfies matches_target().
            - "replace": sidecar is being replaced (drift or revision change).
        target_container_id: last known Docker container ID of the target.
        target_name: name of the target container (e.g. "wg_tik-1").
        operator_scope: the operator scope label value for this deployment.
        consumer_name: name of the consumer that owns this sidecar.
    """

    reason: Literal["orphaned", "target_died", "target_no_longer_matches", "replace"]
    target_container_id: str
    target_name: str
    operator_scope: str
    consumer_name: str
