"""NetworkManager runtime — reconcile loop for Docker network state.

Drives the create/attach/detach lifecycle for managed networks, driven by
SidecarOperator reconcile events.
"""

from __future__ import annotations

from typing import Any

from network_manager.docker_api import (
    build_network_create_kwargs,
    inspect_managed_network,
    validate_existing_network,
)
from network_manager.models import ManagedNetwork
from network_manager.sysctl import HostSysctlRunner


class NetworkManager:
    """Reconciles desired managed Docker networks against actual Docker state.

    For each network in the provided spec list, ensures the Docker network
    exists with the correct driver, subnet, and bridge options, then applies
    any required host sysctl settings (proxy_arp) via nsenter.

    Args:
        client: Docker SDK client.
        sysctl_runner: Host sysctl applier. Defaults to HostSysctlRunner.
    """

    def __init__(
        self, client: Any, sysctl_runner: HostSysctlRunner | None = None
    ) -> None:
        self.client = client
        self.sysctl_runner = sysctl_runner or HostSysctlRunner()

    def ensure_all(self, networks: list[ManagedNetwork]) -> None:
        """Ensure all given networks exist and have correct host configuration.

        For each network:
        - If absent: creates it via Docker API.
        - If present: validates it matches the spec (fails fast on mismatch).
        - If proxy_arp is set: applies the sysctl on the host bridge.

        Args:
            networks: List of network specs to reconcile.

        Raises:
            NetworkContractError: If an existing network violates the desired spec.
            RuntimeError: If applying a host sysctl fails.
        """
        for spec in networks:
            existing = inspect_managed_network(self.client, spec.name)
            if existing is None:
                self.client.networks.create(**build_network_create_kwargs(spec))
            else:
                validate_existing_network(spec, existing)

            if spec.proxy_arp is not None:
                if spec.bridge_name is None:
                    raise RuntimeError(
                        f"invariant violated: network {spec.name!r} has proxy_arp set but no bridge_name"
                    )
                self.sysctl_runner.ensure_proxy_arp(spec.bridge_name, spec.proxy_arp)
