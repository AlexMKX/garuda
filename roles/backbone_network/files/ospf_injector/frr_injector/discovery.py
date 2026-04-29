"""Backbone membership discovery and sidecar state construction.

A membership filter. Applies structural membership rules plus OSPF label
eligibility. All OSPF config parsing and rendering is owned by OspfConfig and
TransitConfig models, invoked by FRRConsumer which owns the full target → sidecar
rendering pipeline.

Membership rules (from design spec):
- container is in 'running' state
- container is attached to backbone_network
- Docker reports a valid IPv4 address for that network attachment
- container is not the operator itself (self-exclusion by container ID)
- container is not labeled as operator-managed (garuda.managed-by)
- if any garuda.frr.* labels are present, OSPF intent must be valid and enabled;
  otherwise the container is excluded (fail-closed label contract)

This module works with ContainerInfo data — it does NOT require a live
Docker client, making it fully testable with synthetic input.
"""

from __future__ import annotations

import logging

from frr_injector._utils import parse_ipv4 as _parse_ipv4
from frr_injector.config import (
    BACKBONE_NETWORK,
    MANAGED_BY_LABEL,
    SIDECAR_REVISION,
    SIDECAR_PREFIX,
    InjectorConfig,
)
from frr_injector.models import ContainerInfo, DesiredSidecar, Target
from frr_injector.ospf_config import OspfConfig, OspfDisabledError

logger = logging.getLogger(__name__)

_FRR_LABEL_PREFIX = "garuda.frr."


def discover_targets(
    containers: list[ContainerInfo],
    config: InjectorConfig,
) -> list[Target]:
    """Discover containers eligible for managed FRR sidecars.

    Applies all structural membership rules from the design spec in order:
    1. running state
    2. attached to backbone_network
    3. valid IPv4 on backbone attachment
    4. not self (by container ID)
    5. not labeled as operator-managed
    6. OSPF label eligibility: if any garuda.frr.* labels present, OSPF intent
       must parse as valid and enabled; fail-closed if disabled or invalid

    Args:
        containers: normalized container metadata from Docker API.
        config: operator configuration with self-exclusion identity.

    Returns:
        A list of Target models for eligible containers.
    """
    targets: list[Target] = []

    for c in containers:
        # Rule 1: must be running
        if c.state != "running":
            logger.debug("skipping %s: state=%s (not running)", c.name, c.state)
            continue

        # Rule 2: must be attached to backbone_network
        if BACKBONE_NETWORK not in c.networks:
            logger.debug("skipping %s: not attached to %s", c.name, BACKBONE_NETWORK)
            continue

        # Rule 3: must have a valid IPv4 on backbone
        raw_ip = c.networks[BACKBONE_NETWORK]
        backbone_ip = _parse_ipv4(raw_ip)
        if backbone_ip is None:
            logger.debug("skipping %s: invalid backbone IPv4 %r", c.name, raw_ip)
            continue

        # Rule 4: must not be self
        if c.id == config.self_container_id:
            logger.debug("skipping %s: self-exclusion (id=%s)", c.name, c.id)
            continue

        # Rule 5: must not be labeled as operator-managed
        if c.labels.get("garuda.managed-by") == MANAGED_BY_LABEL:
            logger.debug(
                "skipping %s: managed-sidecar exclusion (label=%s)",
                c.name,
                MANAGED_BY_LABEL,
            )
            continue

        # Rule 6: if any garuda.frr.* labels present, validate OSPF intent
        has_frr_labels = any(k.startswith(_FRR_LABEL_PREFIX) for k in c.labels)
        if has_frr_labels:
            try:
                ospf_config = OspfConfig.from_labels(c.labels)
            except OspfDisabledError:
                logger.info(
                    "skipping %s: label-managed intent disabled (ospf.enabled!=true)",
                    c.name,
                )
                continue
            except (
                Exception
            ) as exc:  # noqa: BLE001 — pydantic/value errors caught above; keep loop alive for other containers
                logger.error(
                    "skipping %s: label-managed intent invalid: %s",
                    c.name,
                    exc,
                )
                continue
            # from_labels returns None only when enabled key absent, but we
            # already know frr labels are present — treat as invalid if None
            if ospf_config is None:
                logger.error(
                    "skipping %s: label-managed intent has garuda.frr.* labels "
                    "but garuda.frr.ospf.enabled is absent (fail-closed)",
                    c.name,
                )
                continue

        targets.append(
            Target(
                name=c.name,
                container_id=c.id,
                backbone_ipv4=backbone_ip,
            )
        )
        logger.info("discovered target %s with backbone IP %s", c.name, backbone_ip)

    return targets


def desired_sidecar_for(
    target: Target,
    config: InjectorConfig,
) -> DesiredSidecar:
    """Produce the desired sidecar state for one target.

    The sidecar name is deterministic: prefix + target name.
    Required ownership labels are set. No FRR config is rendered here;
    env delivery is owned by the consumer's build_desired_sidecar().

    Args:
        target: an eligible target container.
        config: operator configuration.

    Returns:
        A DesiredSidecar model describing what the managed sidecar should look like.
    """
    sidecar_name = f"{SIDECAR_PREFIX}{target.name}"

    return DesiredSidecar(
        name=sidecar_name,
        target_name=target.name,
        target_container_id=target.container_id,
        network_mode=f"container:{target.container_id}",
        labels={
            "garuda.managed-by": MANAGED_BY_LABEL,
            "garuda.target-container": target.name,
            "garuda.target-container-id": target.container_id,
            "garuda.backbone-network": BACKBONE_NETWORK,
            "garuda.sidecar-revision": SIDECAR_REVISION,
        },
        backbone_ipv4=target.backbone_ipv4,
    )
