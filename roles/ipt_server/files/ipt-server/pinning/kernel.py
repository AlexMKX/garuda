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
import subprocess
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

    # Mask isolating the pinning mark family (PIN_MARK_BASE..+0xff)
    # from any other ct mark scheme present on the box.  The pinning
    # nft chain stamps `ct mark = PIN_MARK_BASE+i` on classification;
    # local portal HTTP connections never traverse that chain and
    # therefore keep ct mark 0, which `--mark <pin>/0xff00` excludes.
    _PIN_MARK_MASK: int = 0xff00

    @classmethod
    def _sync_flush_conntrack(cls, saddr: str) -> None:
        """Drop kernel conntrack flows whose source matches ``saddr``
        AND whose ct mark falls in the pinning range.

        The ct mark filter is the critical part: a naive
        `conntrack -D -s <saddr>` would also tear down the local
        portal HTTP connection that just issued the pin change
        (browser → 1.1.1.1:1111 → REDIRECT to local :80 — the flow
        has saddr=<client> too).  Killing that flow mid-response
        leaves the issuing curl/browser tab waiting forever for a
        response whose conntrack DNAT mapping has vanished, manifest
        as a 30-second timeout instead of the expected 200 / 303.

        With ct mark stamped only on forwarded user flows by the
        pinning prerouting chain, `--mark PIN_MARK_BASE/0xff00`
        deletes ONLY those flows.  Portal connections (ct mark 0)
        survive untouched.

        Best-effort: rc=1 means "no entries matched" and is fine the
        moment after a fresh boot.  pin operations must not be gated
        on the success of this cleanup — it exists purely so a
        client's existing TCP sessions get re-established under the
        freshly-rendered nft ruleset and the fwmark→table lookup it
        implies, instead of riding on the conntrack-saved routing
        decision from before the pin change.
        """
        argv = [
            "conntrack",
            "-D",
            "-s", saddr,
            "--mark", f"{PIN_MARK_BASE:#x}/{cls._PIN_MARK_MASK:#x}",
        ]
        try:
            result = subprocess.run(
                argv,
                capture_output=True,
                text=True,
                timeout=5,
            )
        except FileNotFoundError:
            log.warning(
                "pinning: conntrack binary not found; skipping flush for saddr=%s",
                saddr,
            )
            return
        except subprocess.TimeoutExpired:
            log.warning(
                "pinning: %s timed out (5s); leaving stale flows",
                " ".join(argv),
            )
            return
        if result.returncode not in (0, 1):
            # rc=1 is the "no matching flows" signal in conntrack-tools;
            # treat anything else as a soft warning so we still have a
            # log breadcrumb if the kernel module is missing or the
            # netns lacks /proc/net/nf_conntrack visibility.
            log.warning(
                "pinning: %s returned rc=%d stderr=%r",
                " ".join(argv), result.returncode, result.stderr.strip(),
            )

    async def flush_conntrack(self, saddr: str) -> None:
        """Async wrapper around ``conntrack -D -s <saddr>``.

        Call this AFTER ``reconcile()`` so the next packet from
        ``saddr`` enters the freshly-loaded `pinning prerouting` chain
        with no inherited routing decision from the previous pin
        state.  Without this hook the kernel's conntrack association
        keeps long-lived TCP flows (HTTP/2, persistent connections)
        on whatever route was selected when the original SYN was
        committed, even though `meta mark set` re-fires on every
        packet.  Browsers feel this as "I clicked the new egress but
        my IP didn't change"; curl does not, because each curl
        invocation is a fresh flow with no prior conntrack entry.
        """
        await asyncio.to_thread(self._sync_flush_conntrack, saddr)
