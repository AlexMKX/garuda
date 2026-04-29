"""compose_networks filter — convert nic_attach list into compose-ready dicts.

Input:
    nic_attach (list[str] | str | None): list of NIC short-names or JSON string
        encoding the same. ``None`` and empty values produce empty output.

Output:
    dict with two keys:
        "service" — mapping from Docker network name to service-level attach
                    options (interface_name, gw_priority, etc.)
        "stack"   — mapping from Docker network name to top-level declaration
                    options (name, external, etc.)

Error mode:
    Unknown NIC key or malformed JSON → AnsibleFilterError.

See docs/superpowers/specs/2026-04-16-compose-networks-filter-design.md.
"""

from __future__ import annotations

import json
from typing import Any

from ansible.errors import AnsibleFilterError


# Single source of truth for network topology. Short NIC key → catalog entry.
NETWORK_CATALOG: dict[str, dict[str, Any]] = {
    "backbone": {
        "network_name": "backbone_network",
        "service": {"interface_name": "backbone"},
        "stack": {"name": "backbone_network", "external": True},
    },
    "border": {
        "network_name": "border_network",
        "service": {"interface_name": "border", "gw_priority": 100},
        "stack": {"name": "border_network", "external": True},
    },
}


def _normalize(nic_attach: Any) -> list[str]:
    """Accept list or JSON string; return list of NIC keys."""
    if nic_attach is None or nic_attach == "" or nic_attach == []:
        return []
    if isinstance(nic_attach, list):
        return nic_attach
    if isinstance(nic_attach, str):
        try:
            parsed = json.loads(nic_attach)
        except (ValueError, json.JSONDecodeError) as exc:
            raise AnsibleFilterError(
                f"nic_attach must be list or JSON-encoded list, got: {nic_attach!r}"
            ) from exc
        if not isinstance(parsed, list):
            raise AnsibleFilterError(
                f"nic_attach JSON must decode to a list, got {type(parsed).__name__}: {parsed!r}"
            )
        return parsed
    raise AnsibleFilterError(
        f"nic_attach must be list, JSON string, or None; got {type(nic_attach).__name__}"
    )


def compose_networks(nic_attach: Any) -> dict[str, dict[str, dict[str, Any]]]:
    """Convert ``nic_attach`` into ``{service, stack}`` dicts for compose render."""
    keys = _normalize(nic_attach)

    service: dict[str, dict[str, Any]] = {}
    stack: dict[str, dict[str, Any]] = {}

    for nic in keys:
        if nic not in NETWORK_CATALOG:
            known = sorted(NETWORK_CATALOG.keys())
            raise AnsibleFilterError(f"unknown nic {nic!r}; known: {known}")
        entry = NETWORK_CATALOG[nic]
        name = entry["network_name"]
        service[name] = dict(entry["service"])
        stack[name] = dict(entry["stack"])

    return {"service": service, "stack": stack}


class FilterModule:
    """Ansible filter plugin registration."""

    def filters(self) -> dict[str, Any]:
        return {"compose_networks": compose_networks}
