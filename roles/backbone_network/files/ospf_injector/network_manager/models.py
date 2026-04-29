"""Data models for network_manager.

Defines ManagedNetwork (parsed from OPERATOR_NETWORKS env) and the
normalize_managed_networks helper that converts raw JSON to typed objects.
"""

from __future__ import annotations

from ipaddress import IPv4Network, IPv6Network

from pydantic import BaseModel, Field, model_validator

IPvAnyNetwork = IPv4Network | IPv6Network


class ManagedNetwork(BaseModel):
    """A Docker network managed by the operator.

    Attributes:
        name: Docker network name.
        cidr: Network CIDR block.
        bridge_name: Optional host bridge interface name. Required when proxy_arp is managed.
        proxy_arp: Optional proxy ARP setting (0 = disable, 1 = enable). Requires bridge_name.
    """

    name: str
    cidr: IPvAnyNetwork
    bridge_name: str | None = None
    proxy_arp: int | None = Field(default=None, ge=0, le=1)

    @model_validator(mode="after")
    def validate_bridge_requirements(self) -> "ManagedNetwork":
        """Ensure bridge_name is set whenever proxy_arp is managed."""
        if self.proxy_arp is not None and not self.bridge_name:
            raise ValueError("bridge_name is required when proxy_arp is managed")
        return self


DEFAULT_MANAGED_NETWORKS = [
    ManagedNetwork(name="backbone_network", cidr="172.30.0.0/24"),
    ManagedNetwork(
        name="border_network",
        cidr="172.29.0.0/24",
        bridge_name="br-border",
        proxy_arp=1,
    ),
]


def normalize_managed_networks(
    overrides: list[ManagedNetwork] | None,
) -> list[ManagedNetwork]:
    """Merge operator-supplied network overrides with the hardcoded defaults.

    Defaults are always present. An override that names an existing default
    performs a *patch* — only fields that were explicitly set in the override
    replace the corresponding default fields. New names are appended in the
    order they appear in `overrides`.

    Args:
        overrides: Operator-supplied network definitions, or None/empty list
            to use defaults as-is.

    Returns:
        Ordered list of ManagedNetwork instances with defaults first, then
        any new networks from overrides.

    Raises:
        ValueError: If `overrides` contains duplicate network names.
    """
    merged: dict[str, ManagedNetwork] = {
        network.name: network.model_copy(deep=True)
        for network in DEFAULT_MANAGED_NETWORKS
    }

    if not overrides:
        return list(merged.values())

    seen_override_names: set[str] = set()
    for network in overrides:
        if network.name in seen_override_names:
            raise ValueError(f"duplicate network name: {network.name}")
        seen_override_names.add(network.name)

        if network.name in merged:
            patch = network.model_dump(exclude_unset=True)
            merged[network.name] = merged[network.name].model_copy(update=patch)
        else:
            merged[network.name] = network

    return list(merged.values())
