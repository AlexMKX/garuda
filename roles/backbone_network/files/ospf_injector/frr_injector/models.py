"""Desired and actual state models for OSPF injector targets and sidecars.

These are pure data models — they carry no Docker API interaction logic.
The discovery layer populates them from container metadata, and the
reconcile layer compares desired vs actual to plan actions.
"""

from __future__ import annotations

import ipaddress

from pydantic import BaseModel

from sidecar_operator.models import ContainerInfo  # noqa: F401 — re-export


class Target(BaseModel):
    """An eligible container that should receive a managed FRR sidecar.

    Attributes:
        name: container name
        container_id: Docker container ID (used for network_mode binding)
        backbone_ipv4: the container's IPv4 address on backbone_network
    """

    name: str
    container_id: str
    backbone_ipv4: ipaddress.IPv4Address


class DesiredSidecar(BaseModel):
    """The desired state of a managed FRR sidecar for one target.

    Attributes:
        name: deterministic sidecar container name
        target_name: the target container this sidecar is bound to
        target_container_id: current Docker container ID of target_name
        network_mode: Docker network_mode value (container:<target-id>)
        labels: required labels for ownership and binding
        backbone_ipv4: the target's backbone IP (used for sidecar creation)
    """

    name: str
    target_name: str
    target_container_id: str = ""
    network_mode: str
    labels: dict[str, str]
    backbone_ipv4: ipaddress.IPv4Address


class ActualSidecar(BaseModel):
    """A running managed sidecar discovered by ownership labels.

    Represents the actual state of a sidecar that the operator previously
    created and is tracking via labels. Used by the reconcile planner
    to compare against desired state.

    Attributes:
        container_id: Docker container ID (needed for removal/replacement).
        name: container name.
        target_container_name: value of 'garuda.target-container' label.
        target_container_id: value of 'garuda.target-container-id' label.
        backbone_network: value of 'garuda.backbone-network' label.
        sidecar_revision: value of 'garuda.sidecar-revision' label.
        network_mode: Docker HostConfig.NetworkMode.
        state: container state string ('running', 'exited', 'created', etc.).
    """

    container_id: str
    name: str
    target_container_name: str
    target_container_id: str = ""
    backbone_network: str
    sidecar_revision: str = ""
    network_mode: str
    state: str = "running"
    target_netns_inode: str | None = None
    sidecar_netns_inode: str | None = None
