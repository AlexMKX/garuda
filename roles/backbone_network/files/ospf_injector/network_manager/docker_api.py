"""Docker API wrapper for network_manager.

Handles network creation, attachment, and removal via the Docker SDK.
Translates SDK errors to DockerUnavailableError / NetworkContractError.
"""

from __future__ import annotations

from typing import Any

import docker.types  # type: ignore[import-untyped]

from network_manager.models import ManagedNetwork


class NetworkContractError(ValueError):
    """Raised when an existing Docker network violates the desired contract."""


def inspect_managed_network(client: Any, name: str) -> dict[str, Any] | None:
    """Return the attrs dict for a Docker network by name, or None if absent.

    Args:
        client: A docker SDK client.
        name: The exact network name to look up.

    Returns:
        The raw attrs dict from the first matching network object, or None.
    """
    matches = client.networks.list(names=[name])
    if not matches:
        return None
    return matches[0].attrs


def build_network_create_kwargs(spec: ManagedNetwork) -> dict[str, Any]:
    """Build keyword arguments for docker.client.networks.create() from a ManagedNetwork spec.

    Args:
        spec: The desired network configuration.

    Returns:
        A dict suitable for unpacking into networks.create(**kwargs).
    """
    ipam_pool = docker.types.IPAMPool(subnet=str(spec.cidr))
    ipam_config = docker.types.IPAMConfig(pool_configs=[ipam_pool])
    options: dict[str, str] = {}
    if spec.bridge_name:
        options["com.docker.network.bridge.name"] = spec.bridge_name

    kwargs: dict[str, Any] = {
        "name": spec.name,
        "driver": "bridge",
        "ipam": ipam_config,
    }
    if options:
        kwargs["options"] = options
    return kwargs


def validate_existing_network(spec: ManagedNetwork, attrs: dict[str, Any]) -> None:
    """Validate that an existing Docker network matches the desired spec.

    Raises:
        NetworkContractError: If driver or subnet do not match. If spec.bridge_name
            is set, also validates that the existing network uses the same bridge name.
            When spec.bridge_name is None, the bridge check is skipped (the operator
            does not own bridge naming for that network).
    """
    actual_driver = attrs.get("Driver", "")
    if actual_driver != "bridge":
        raise NetworkContractError(
            f"driver mismatch for {spec.name}: expected bridge, got {actual_driver}"
        )

    actual_subnet = ""
    configs = attrs.get("IPAM", {}).get("Config", [])
    if configs:
        actual_subnet = configs[0].get("Subnet", "")
    if actual_subnet != str(spec.cidr):
        raise NetworkContractError(
            f"subnet mismatch for {spec.name}: expected {spec.cidr}, got {actual_subnet}"
        )

    if spec.bridge_name is not None:
        actual_bridge_name = attrs.get("Options", {}).get(
            "com.docker.network.bridge.name"
        )
        if actual_bridge_name != spec.bridge_name:
            raise NetworkContractError(
                f"bridge mismatch for {spec.name}: expected {spec.bridge_name},"
                f" got {actual_bridge_name}"
            )
