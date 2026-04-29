"""Pydantic configuration models for the OSPF injector operator.

Defines the static configuration surface that is provided at operator
startup time (from a rendered config file or environment). Runtime
state like container IPs is NOT part of this model — that is derived
by the discovery layer.

Sidecar image identity is intentionally not part of runtime reconcile
inputs; it remains an internal constant used only when creating a sidecar.

Workload profiles and advertised prefixes are hardcoded in render.py and
are not configurable at operator startup time.
"""

from __future__ import annotations

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from network_manager.models import ManagedNetwork, normalize_managed_networks

# ---------------------------------------------------------------------------
# Module-level constants: hardcoded values that never change between deployments
# ---------------------------------------------------------------------------

BACKBONE_NETWORK = "backbone_network"
MANAGED_BY_LABEL = "ospf-injector"
SIDECAR_PREFIX = "ospf-"
FRR_SIDECAR_IMAGE = "garuda/frr-sidecar:latest"
SIDECAR_REVISION = "3"  # bumped: garuda.backbone-ipv4 label removed (drift via netns inode)

# Transit routing constants — SSOT for all transit-related parameters.
# These coordinate between the transit provider (tagged OSPF default origination)
# and transit consumers (PBR table + watcher). Must match on both sides.
TRANSIT_TAG = 201
TRANSIT_TABLE = 201
TRANSIT_METRIC = 10
TRANSIT_METRIC_TYPE = 2
TRANSIT_ROUTE_MAP = "TRANSIT-DEFAULT-TAG"


class InjectorConfig(BaseSettings):
    """Top-level operator configuration.

    Attributes:
        self_container_id: The container ID of the operator itself, used for
            self-exclusion during discovery.
        operator_scope: The operator scope label value for this deployment,
            matched against garuda.operator-scope on candidate containers.
        networks: Managed Docker networks to be provisioned before the operator
            loop starts. Defaults include backbone_network and border_network;
            accepts JSON override via OPERATOR_NETWORKS env var.
    """

    model_config = SettingsConfigDict(env_prefix="OPERATOR_", extra="ignore")

    self_container_id: str = ""
    operator_scope: str = ""
    networks: list[ManagedNetwork] = Field(default_factory=list)

    @model_validator(mode="after")
    def normalize_networks(self) -> "InjectorConfig":
        """Apply default network definitions and merge any operator overrides."""
        self.networks = normalize_managed_networks(self.networks)
        return self
