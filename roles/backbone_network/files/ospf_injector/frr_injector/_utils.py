"""Shared parsing utilities for frr_injector models."""

from __future__ import annotations

import ipaddress
import re

_IFACE_RE = re.compile(r"^[a-zA-Z0-9_.:-]+$")


def parse_interfaces(raw: str) -> list[str]:
    """Parse a CSV interface list, validate names, deduplicate.

    Returns an empty list for an empty string.
    Raises ValueError if any name is empty or contains invalid characters.
    """
    if raw == "":
        return []
    parts = [part.strip() for part in raw.split(",")]
    if any(not part for part in parts):
        raise ValueError("empty interface name in CSV")
    if any(_IFACE_RE.match(part) is None for part in parts):
        raise ValueError(f"invalid interface name in: {parts}")
    seen: set[str] = set()
    result: list[str] = []
    for part in parts:
        if part not in seen:
            seen.add(part)
            result.append(part)
    return result


def parse_ipv4(raw: str) -> ipaddress.IPv4Address | None:
    """Parse a string as an IPv4 address, returning None on failure."""
    if not raw:
        return None
    try:
        return ipaddress.IPv4Address(raw)
    except (ipaddress.AddressValueError, ValueError):
        return None
