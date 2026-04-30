"""Kernel-side reconciliation for the pinning subsystem.

Owns three categories of kernel state, all tagged with PINNING_PROTO
when expressible:

- N ip rules (one per egress): `fwmark PIN_MARK_BASE+i lookup
  TABLE_BASE+i` at priority PINNING_RULE_PRIORITY (100), installed
  once at startup.  No DNS escape goto-rule: DNS_MARK (0x201) does
  not match any pinning fwmark (0xA00+i), so DNS-marked packets fall
  through to geo-PBR or main automatically.
- N per-egress routing tables (TABLE_BASE+i) holding a default route;
  liveness updates these.
- the `ip pinning` nft table (saddr → mark classification);
  reconcile() renders+replaces the whole thing per pin change.

pyroute2 >=0.9 constructs an asyncore event loop in IPRoute.__init__
and rejects dst='default' with EOPNOTSUPP for type=blackhole, so all
IPRoute calls go through asyncio.to_thread and use dst='0.0.0.0/0'
explicitly.  Same to_thread treatment for nftables.Nftables().cmd().
"""
from __future__ import annotations

import asyncio
import logging
from typing import Dict, Mapping, Optional

import nftables
from pyroute2 import IPRoute

from pinning.nft_renderer import PIN_MARK_BASE, NftRenderer


log = logging.getLogger(__name__)

PINNING_PROTO: int = 201
PINNING_TABLE_BASE: int = 300
PINNING_RULE_PRIORITY: int = 100


def _table_for_index(i: int) -> int:
    return PINNING_TABLE_BASE + i


def _mark_for_index(i: int) -> int:
    return PIN_MARK_BASE + i


class KernelReconciler:
    """Translate pinning state into ip rule + ip route + nft objects."""

    # pyroute2 0.9.x rejects dst="default" with EOPNOTSUPP for type=blackhole.
    _DEFAULT_DST = "0.0.0.0/0"

    def __init__(
        self,
        *,
        catalog: Mapping[str, object],
        portal_addr: str,
        portal_port: int,
        api_port: int,
        ttl_seconds: int = 86400,
    ) -> None:
        self._renderer = NftRenderer(
            catalog=catalog,
            portal_addr=portal_addr,
            portal_port=portal_port,
            api_port=api_port,
            ttl_seconds=ttl_seconds,
        )

    def _egress_index(self, egress: str) -> int:
        keys = self._renderer.sorted_keys
        try:
            return keys.index(egress)
        except ValueError as exc:
            raise ValueError(
                f"egress {egress!r} not in catalog "
                f"{keys!r}"
            ) from exc

    # ------------------------------------------------------------------
    # Synchronous helpers — run in worker threads via asyncio.to_thread.
    # ------------------------------------------------------------------

    @classmethod
    def _sync_install_static(cls, n_egresses: int) -> None:
        with IPRoute() as ipr:
            ipr.flush_rules(proto=PINNING_PROTO)
            for i in range(n_egresses):
                ipr.rule(
                    "add",
                    priority=PINNING_RULE_PRIORITY,
                    fwmark=_mark_for_index(i),
                    table=_table_for_index(i),
                    proto=PINNING_PROTO,
                )

    @classmethod
    def _sync_update_liveness(
        cls,
        table: int,
        alive: bool,
        nh_ip: Optional[str],
        nh_dev: Optional[str],
    ) -> None:
        with IPRoute() as ipr:
            if not alive:
                ipr.route(
                    "replace",
                    dst=cls._DEFAULT_DST,
                    table=table,
                    type="blackhole",
                    proto=PINNING_PROTO,
                )
                return
            oif = ipr.link_lookup(ifname=nh_dev)[0] if nh_dev else None
            kwargs: Dict[str, object] = {
                "dst": cls._DEFAULT_DST,
                "table": table,
                "proto": PINNING_PROTO,
            }
            if oif is not None:
                kwargs["oif"] = oif
            if nh_ip is not None:
                kwargs["gateway"] = nh_ip
            ipr.route("replace", **kwargs)

    @staticmethod
    def _sync_apply_nft(ruleset_text: str) -> None:
        nft = nftables.Nftables()
        # Idempotent delete; ignore rc.
        nft.cmd("delete table ip pinning")
        rc, _output, error = nft.cmd(ruleset_text)
        if rc != 0:
            raise RuntimeError(f"nft load failed: {error}")

    # ------------------------------------------------------------------
    # Public async interface.
    # ------------------------------------------------------------------

    async def install_static_rules(self) -> None:
        """Idempotent startup: wipe our ip rules, install fwmark→table.

        Also seeds every per-egress table with a blackhole default so
        unresolved egresses fail closed before liveness reports in.
        Caller invokes once at process start.
        """
        keys = self._renderer.sorted_keys
        await asyncio.to_thread(self._sync_install_static, len(keys))
        for key in keys:
            await self.update_egress_liveness(
                egress=key, alive=False, nh_ip=None, nh_dev=None,
            )
        log.info(
            "pinning: static rules installed for %d egresses, marks=0x%x..0x%x, tables=%d..%d",
            len(keys),
            _mark_for_index(0) if keys else 0,
            _mark_for_index(len(keys) - 1) if keys else 0,
            _table_for_index(0) if keys else 0,
            _table_for_index(len(keys) - 1) if keys else 0,
        )

    async def update_egress_liveness(
        self,
        egress: str,
        alive: bool,
        nh_ip: Optional[str] = None,
        nh_dev: Optional[str] = None,
    ) -> None:
        """Install the per-egress default route (live or blackhole)."""
        i = self._egress_index(egress)
        table = _table_for_index(i)
        await asyncio.to_thread(
            self._sync_update_liveness, table, alive, nh_ip, nh_dev,
        )

    async def reconcile(self, pins: Mapping[str, str]) -> None:
        """Render+apply the pinning nft ruleset for the given saddr→egress map."""
        ruleset = self._renderer.render(pins)
        await asyncio.to_thread(self._sync_apply_nft, ruleset)
