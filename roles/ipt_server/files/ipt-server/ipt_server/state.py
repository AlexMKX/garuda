"""Shared mutable runtime state for ipt_server."""

from __future__ import annotations
import threading
from typing import TYPE_CHECKING, Dict

if TYPE_CHECKING:
    from Config import MySettings
    from Router import Router

CONFIG: MySettings | None = None
ROUTER: Router | None = None
INTERFACE_HEALTH: dict[str, bool] = {}

# Snapshot of ifname -> ifindex owned by tasks/interface_monitor.py.
# Writers: only interface_monitor under INTERFACES_LOCK.
# Readers: only RouteObject.interfaces under INTERFACES_LOCK, with copy.
INTERFACES: Dict[str, int] = {}
INTERFACES_LOCK = threading.Lock()
