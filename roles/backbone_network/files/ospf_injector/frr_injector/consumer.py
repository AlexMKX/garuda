"""FRRConsumer: frr_injector as a SidecarOperatorConsumer.

Implements the SidecarOperatorConsumer protocol so that the OSPF injector
logic can run as a consumer of the shared sidecar_operator framework.

The consumer owns:
- target matching (backbone membership + OSPF label intent)
- desired sidecar spec construction (FRR config via env vars, model-driven)
- reconcile hook: validates declared interfaces against live container state
"""

from __future__ import annotations

import base64
import binascii
import logging
from typing import TYPE_CHECKING

from pydantic import ValidationError

from frr_injector.config import (
    BACKBONE_NETWORK,
    FRR_SIDECAR_IMAGE,
    InjectorConfig,
    SIDECAR_REVISION,
    TRANSIT_TAG,
)
from frr_injector._utils import parse_ipv4 as _parse_ipv4
from sidecar_operator.docker_api import list_workload_interfaces
from frr_injector.ospf_config import OspfConfig, OspfDisabledError
from frr_injector.transit_config import TransitConfig
from frr_injector.render import render_daemons, render_frr_conf, render_vtysh_conf
from sidecar_operator.consumer_api import SidecarOperatorConsumer
from sidecar_operator.models import (
    DesiredSidecarSpec,
    SharedNamespaces,
    SidecarStopContext,
)

if TYPE_CHECKING:
    from docker import DockerClient
    from docker.models.containers import Container

logger = logging.getLogger(__name__)


class FRRConsumer(SidecarOperatorConsumer):
    """SidecarOperatorConsumer implementation for FRR/OSPF sidecars.

    Matches backbone-attached containers and produces DesiredSidecarSpec
    instances backed by rendered FRR configuration delivered via env vars.
    Uses model-driven rendering via OspfConfig.render_block() rather than legacy Jinja2 templates.
    """

    name = "ospf"
    sidecar_revision = SIDECAR_REVISION

    def __init__(self, config: InjectorConfig) -> None:
        self.config = config

    # ------------------------------------------------------------------
    # Protocol: matches_target
    # ------------------------------------------------------------------

    def matches_target(self, container: "Container") -> bool:
        """Return True if this container is eligible for an FRR sidecar.

        Rules applied in order:
        1. garuda.operator-scope label matches config.operator_scope
        2. Not labeled as sidecar-operator-managed (skip own sidecars)
        3. Attached to backbone_network with a valid IPv4
        4. Not the operator itself (self_container_id exclusion)
        5. If OSPF labels present and disabled or invalid → False
           If no OSPF labels → True (no sidecar will be created, but target is eligible)
        """
        labels = container.labels or {}

        # Rule 1: scope guard
        if labels.get("garuda.operator-scope") != self.config.operator_scope:
            return False

        # Rule 2: skip already-managed sidecars
        if labels.get("garuda.managed-by") == "sidecar-operator":
            return False

        # Rule 3: backbone attachment + valid IPv4
        networks = container.attrs.get("NetworkSettings", {}).get("Networks", {})
        if BACKBONE_NETWORK not in networks:
            return False
        raw_ip = networks[BACKBONE_NETWORK].get("IPAddress", "")
        backbone_ip = _parse_ipv4(raw_ip)
        if backbone_ip is None:
            return False

        # Rule 4: self-exclusion
        if container.id == self.config.self_container_id:
            return False

        # Rule 5: if OSPF labels present, validate them; disabled or invalid = exclude
        try:
            ospf_config = OspfConfig.from_labels(labels)
        except OspfDisabledError:
            return False
        except (ValidationError, ValueError) as exc:
            logger.error(
                "matches_target: invalid OSPF labels for %s: %s",
                container.name,
                exc,
            )
            return False
        # ospf_config is OspfConfig | None
        # None = no OSPF labels = eligible (no sidecar created)
        # OspfConfig = valid labels = eligible

        return True

    # ------------------------------------------------------------------
    # Protocol: shared_namespaces
    # ------------------------------------------------------------------

    def shared_namespaces(self, target: "Container") -> SharedNamespaces:
        return SharedNamespaces(network=True, pid=False, ipc=False)

    # ------------------------------------------------------------------
    # Protocol: build_desired_sidecar
    # ------------------------------------------------------------------

    def build_desired_sidecar(self, target: "Container") -> DesiredSidecarSpec | None:
        """Build the DesiredSidecarSpec for this target using model-driven rendering.

        Parses OspfConfig and TransitConfig from container labels, renders
        frr.conf via render_block(), and
        packages the output as base64-encoded environment variables for the
        FRR sidecar entrypoint.

        Returns None if the target cannot produce a valid sidecar spec
        (e.g. OSPF disabled, invalid labels, or render failure).
        """
        target_name = target.name.lstrip("/")
        target_id = target.id
        labels = target.labels or {}

        # Extract backbone IPv4
        networks = target.attrs.get("NetworkSettings", {}).get("Networks", {})
        raw_ip = networks.get(BACKBONE_NETWORK, {}).get("IPAddress", "")
        backbone_ipv4 = _parse_ipv4(raw_ip)
        if backbone_ipv4 is None:
            logger.error(
                "build_desired_sidecar: no valid backbone IPv4 for %s", target_name
            )
            return None

        # Parse OSPF config from labels
        try:
            ospf_config = OspfConfig.from_labels(labels)
        except OspfDisabledError:
            return None
        except (ValidationError, ValueError) as exc:
            logger.error(
                "build_desired_sidecar: invalid OSPF labels for %s: %s",
                target_name,
                exc,
            )
            return None

        # No OSPF labels at all → no sidecar
        if ospf_config is None:
            return None

        # Parse transit config from labels
        try:
            transit_config = TransitConfig.from_labels(labels)
        except (ValidationError, ValueError) as exc:
            logger.error(
                "build_desired_sidecar: invalid transit labels for %s: %s",
                target_name,
                exc,
            )
            return None

        # Decode extra_b64 body for raw mode
        extra_body: str | None = None
        if ospf_config.has_extra_b64:
            raw_b64 = labels.get("garuda.frr.extra_b64")
            if raw_b64:
                try:
                    extra_body = base64.b64decode(raw_b64).decode("utf-8")
                except (binascii.Error, UnicodeDecodeError) as exc:
                    logger.error(
                        "build_desired_sidecar: invalid extra_b64 for %s: %s",
                        target_name,
                        exc,
                    )
                    return None

        # Transit provider implies default_originate by construction:
        # a provider's whole purpose is to originate the tagged default route.
        if transit_config and transit_config.provider:
            ospf_config.default_originate = True
            ospf_config.transit_provider = True

        # Render FRR config using model methods. Transit PBR is handled by
        # transit_watcher in the sidecar, not by FRR — so transit_config does
        # not participate in frr.conf rendering.
        frr_conf = render_frr_conf(
            hostname=f"{target_name}-frr",
            ospf_config=ospf_config,
            extra_body=extra_body,
        )

        transit_enabled = transit_config is not None and bool(transit_config.interfaces)
        daemons = render_daemons()
        vtysh = render_vtysh_conf()

        env: dict[str, str] = {
            "FRR_CONF_B64": base64.b64encode(frr_conf.encode()).decode(),
            "DAEMONS_B64": base64.b64encode(daemons.encode()).decode(),
            "VTYSH_CONF_B64": base64.b64encode(vtysh.encode()).decode(),
            "BACKBONE_IP": str(backbone_ipv4),
        }
        if transit_enabled:
            env["PBR_TRANSIT_TAG"] = str(TRANSIT_TAG)
            env["PBR_TRANSIT_INTERFACES"] = ",".join(transit_config.interfaces)

        sidecar_labels: dict[str, str] = {
            "garuda.managed-by": "sidecar-operator",
            "garuda.operator-scope": self.config.operator_scope,
            "garuda.sidecar-consumer": self.name,
            "garuda.target-container": target_name,
            "garuda.target-container-id": target_id,
            "garuda.sidecar-revision": self.sidecar_revision,
        }

        return DesiredSidecarSpec(
            consumer_name=self.name,
            target_name=target_name,
            target_container_id=target_id,
            sidecar_name=f"ospf-{target_name}",
            image=FRR_SIDECAR_IMAGE,
            labels=sidecar_labels,
            environment=env,
            shared_namespaces=SharedNamespaces(network=True, pid=False, ipc=False),
            capabilities=["NET_ADMIN", "NET_RAW", "SYS_ADMIN"],
        )

    # ------------------------------------------------------------------
    # Protocol: lifecycle hooks
    # ------------------------------------------------------------------

    def on_reconcile(
        self,
        target: "Container",
        sidecar: "Container | None",
        docker: "DockerClient",
    ) -> None:
        """Validate declared interfaces against live container state.

        If the target has label-managed OSPF intent in compact mode, check that
        all declared OSPF interfaces exist in the container's actual network namespace.
        Raises RuntimeError if any declared interface is missing.
        """
        target_name = target.name.lstrip("/")
        labels = target.labels or {}

        try:
            ospf_config = OspfConfig.from_labels(labels)
        except (
            Exception
        ) as exc:  # noqa: BLE001 — on_reconcile must not crash the event loop
            logger.debug("on_reconcile unexpected fallback: %s", exc, exc_info=True)
            return

        if ospf_config is None or ospf_config.has_extra_b64:
            return

        # Interface validation only applies to compact mode
        declared = set(ospf_config.interfaces)
        try:
            actual_ifaces = list_workload_interfaces(docker, target.id)
        except (
            Exception
        ) as exc:  # noqa: BLE001 — re-raises as RuntimeError; surface to reconcile loop
            raise RuntimeError(
                f"on_reconcile: failed to list interfaces for {target_name}: {exc}"
            ) from exc

        missing = declared - actual_ifaces
        if missing:
            raise RuntimeError(
                f"on_reconcile: declared OSPF interfaces {sorted(missing)} "
                f"not found in {target_name} (actual: {sorted(actual_ifaces)})"
            )

    def on_sidecar_started(
        self,
        target: "Container",
        sidecar: "Container",
        docker: "DockerClient",
    ) -> None:
        """No-op for now."""

    def before_sidecar_stopped(
        self,
        context: SidecarStopContext,
        sidecar: "Container",
        docker: "DockerClient",
    ) -> None:
        """No-op for now."""
