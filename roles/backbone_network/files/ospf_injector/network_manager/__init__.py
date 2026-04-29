"""network_manager — Docker network lifecycle for the ospf_injector operator.

Exposes ManagedNetwork and normalize_managed_networks for use by the SidecarOperator.
"""

from network_manager.models import ManagedNetwork, normalize_managed_networks

__all__ = ["ManagedNetwork", "normalize_managed_networks"]
