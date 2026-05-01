"""KernelReconciler tests against the nft + ip rule architecture.

The reconciler owns three things:
  * static `ip rule fwmark <pin mark[i]> lookup TABLE_BASE+i` entries
    (one per egress, installed once),
  * per-egress routing tables (the default route in each is owned by
    the liveness loop via update_egress_liveness),
  * a render-and-replace cycle of the `pinning` nft table on every
    pin/unpin.

There is NO DNS escape goto-rule in RPDB: DNS_MARK (0x201) does not
match any pinning fwmark (0xA00+i), so DNS-marked packets fall
through to the geo-PBR rule (priority 32000) or main automatically.
"""
from __future__ import annotations

import asyncio
from unittest.mock import MagicMock, patch

import pytest

from pinning import kernel
from pinning.kernel import KernelReconciler


def _catalog(*keys):
    return {k: object() for k in keys}


def _make_iproute_ctx():
    patcher = patch("pinning.kernel.IPRoute")
    cls = patcher.start()
    instance = MagicMock()
    cls.return_value.__enter__.return_value = instance
    cls.return_value.__exit__.return_value = False
    return patcher, instance


def _make_nft_ctx():
    patcher = patch("pinning.kernel.nftables.Nftables")
    cls = patcher.start()
    instance = MagicMock()
    instance.cmd.return_value = (0, "", "")
    cls.return_value = instance
    return patcher, instance


def test_install_static_rules_flushes_proto_rules_first():
    """install_static_rules removes any leftover proto=PINNING_PROTO
    state before installing the new fwmark→table mapping (idempotent
    re-run after restart with a different catalog must not leak rules)."""
    pr_patcher, mock_iproute = _make_iproute_ctx()
    nft_patcher, _ = _make_nft_ctx()
    try:
        rec = KernelReconciler(
            catalog=_catalog("outer-de", "outer-pt"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.install_static_rules())
        mock_iproute.flush_rules.assert_called_with(proto=kernel.PINNING_PROTO)
    finally:
        pr_patcher.stop()
        nft_patcher.stop()


def test_install_static_rules_emits_one_fwmark_lookup_per_egress():
    """One ip rule per egress: fwmark=PIN_MARK_BASE+i lookup TABLE_BASE+i."""
    pr_patcher, mock_iproute = _make_iproute_ctx()
    nft_patcher, _ = _make_nft_ctx()
    try:
        from pinning.nft_renderer import PIN_MARK_BASE
        rec = KernelReconciler(
            catalog=_catalog("a", "b", "c"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.install_static_rules())

        per_egress = [
            c for c in mock_iproute.rule.call_args_list
            if c.kwargs.get("priority") == kernel.PINNING_RULE_PRIORITY
        ]
        assert len(per_egress) == 3
        seen = {(c.kwargs["fwmark"], c.kwargs["table"]) for c in per_egress}
        assert seen == {
            (PIN_MARK_BASE + 0, kernel.PINNING_TABLE_BASE + 0),
            (PIN_MARK_BASE + 1, kernel.PINNING_TABLE_BASE + 1),
            (PIN_MARK_BASE + 2, kernel.PINNING_TABLE_BASE + 2),
        }
        for c in per_egress:
            assert c.kwargs["proto"] == kernel.PINNING_PROTO
    finally:
        pr_patcher.stop()
        nft_patcher.stop()


def test_install_static_rules_does_not_emit_dns_escape_goto():
    """No goto-rule for DNS_MARK in RPDB.

    Pinning marks (0xA00+i) do not overlap DNS_MARK (0x201), so the
    fwmark→table rules cannot accidentally divert DNS traffic; the
    DNS hijack opt-out lives in dns_dnat_ipt_server (pin bit match),
    not in RPDB.  Asserting absence pins the contract.
    """
    pr_patcher, mock_iproute = _make_iproute_ctx()
    nft_patcher, _ = _make_nft_ctx()
    try:
        rec = KernelReconciler(
            catalog=_catalog("hub"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.install_static_rules())
        for c in mock_iproute.rule.call_args_list:
            assert c.kwargs.get("action") != "goto", (
                f"unexpected goto rule installed by pinning: {c.kwargs}"
            )
    finally:
        pr_patcher.stop()
        nft_patcher.stop()


def test_install_static_rules_initialises_egress_tables_with_blackhole():
    """Each egress table gets a blackhole default until liveness reports in."""
    pr_patcher, mock_iproute = _make_iproute_ctx()
    nft_patcher, _ = _make_nft_ctx()
    try:
        rec = KernelReconciler(
            catalog=_catalog("outer-de", "outer-pt"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.install_static_rules())
        replace_calls = [
            c for c in mock_iproute.route.call_args_list
            if c.args == ("replace",) and c.kwargs.get("type") == "blackhole"
        ]
        assert len(replace_calls) == 2
    finally:
        pr_patcher.stop()
        nft_patcher.stop()


def test_reconcile_renders_and_loads_nft_ruleset():
    """reconcile(pins) deletes the old table then loads the rendered text."""
    nft_patcher, mock_nft = _make_nft_ctx()
    try:
        rec = KernelReconciler(
            catalog=_catalog("hub"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.reconcile({"172.30.0.3": "hub"}))

        cmds = [c.args[0] for c in mock_nft.cmd.call_args_list]
        assert any("delete table ip pinning" in c for c in cmds)
        loaded = next(
            c for c in cmds
            if "table ip pinning" in c and "set pinned_hub" in c
        )
        assert "172.30.0.3 timeout" in loaded
        assert "ip saddr @pinned_hub meta mark set 0xa00" in loaded
    finally:
        nft_patcher.stop()


def test_reconcile_propagates_nft_failure_with_error_text():
    """A non-zero rc on load raises with the nft stderr embedded."""
    nft_patcher, mock_nft = _make_nft_ctx()
    try:
        # Deletion call rc=0 (idempotent); load call rc=1.
        mock_nft.cmd.side_effect = [(0, "", ""), (1, "", "syntax error near :-150")]
        rec = KernelReconciler(
            catalog=_catalog("hub"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        with pytest.raises(RuntimeError, match="syntax error near"):
            asyncio.run(rec.reconcile({}))
    finally:
        nft_patcher.stop()


def test_update_egress_liveness_replaces_per_table_default():
    """Liveness path unchanged: replace default route in TABLE_BASE+i."""
    pr_patcher, mock_iproute = _make_iproute_ctx()
    try:
        rec = KernelReconciler(
            catalog=_catalog("outer-de", "outer-pt"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.update_egress_liveness(
            egress="outer-pt", alive=True, nh_ip="10.9.19.2", nh_dev=None,
        ))
        replace = next(
            c for c in mock_iproute.route.call_args_list
            if c.args == ("replace",)
        )
        assert replace.kwargs["table"] == kernel.PINNING_TABLE_BASE + 1
        assert replace.kwargs["gateway"] == "10.9.19.2"
        assert replace.kwargs["dst"] == "0.0.0.0/0"  # not 'default' — pyroute2 0.9 quirk
    finally:
        pr_patcher.stop()


def test_update_egress_liveness_dead_writes_blackhole():
    """alive=False writes a blackhole default into the egress table."""
    pr_patcher, mock_iproute = _make_iproute_ctx()
    try:
        rec = KernelReconciler(
            catalog=_catalog("hub"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.update_egress_liveness(
            egress="hub", alive=False,
        ))
        replace = next(
            c for c in mock_iproute.route.call_args_list
            if c.args == ("replace",)
        )
        assert replace.kwargs["type"] == "blackhole"
    finally:
        pr_patcher.stop()


def test_flush_conntrack_filters_by_saddr_and_pinning_mark_mask():
    """flush_conntrack(saddr) drops ONLY flows that were classified by
    the pinning chain (ct mark in 0xA00..0xAFF), leaving local portal
    HTTP connections alone (their ct mark is 0).

    Without the mark-mask filter, `conntrack -D -s <saddr>` is too
    broad: it also kills the browser-to-portal HTTP connection that
    just issued the pin change.  The kernel forgets the redirect
    DNAT mapping, the in-flight HTTP response cannot be matched
    back to the open TCP socket, and curl / the browser tab times
    out instead of getting its 200 (or 303 for the html redirect).

    The pinning chain stamps `ct mark` alongside `meta mark` on
    every classification rule (see test_classification_rules_also_
    stamp_ct_mark_for_post_pin_flush).  PIN_MARK_BASE=0xA00, masks
    are 0xff00 to cover up to 256 egresses without overlapping
    PBR_MARK (0x200 family) or DNS_MARK (0x201).

    argv contract: explicit -s and --mark to keep the shell-out
    surface zero and the tuple search the kernel performs as
    narrow as possible.
    """
    from pinning.nft_renderer import PIN_MARK_BASE
    pr_patcher, _ = _make_iproute_ctx()
    nft_patcher, _ = _make_nft_ctx()
    run_patcher = patch("pinning.kernel.subprocess.run")
    run_mock = run_patcher.start()
    run_mock.return_value = MagicMock(returncode=0, stdout="", stderr="")
    try:
        rec = KernelReconciler(
            catalog=_catalog("hub"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.flush_conntrack("192.0.2.42"))

        assert run_mock.call_count == 1
        argv = run_mock.call_args.args[0]
        assert argv[0] == "conntrack"
        assert "-D" in argv

        # -s with the saddr value passed as a separate argv element so
        # there is no shell interpolation surface.
        s_idx = argv.index("-s")
        assert argv[s_idx + 1] == "192.0.2.42"

        # --mark with mask covering the entire pinning mark range.
        # PIN_MARK_BASE=0xA00, mask=0xff00 covers 0xA00..0xAFF.
        # Format: "<mark>/<mask>" per conntrack-tools convention.
        # We render hex/hex for self-documenting argv readable in
        # log lines and strace dumps without a mental decimal⇄hex
        # conversion.
        m_idx = argv.index("--mark")
        assert argv[m_idx + 1] == f"{PIN_MARK_BASE:#x}/0xff00", (
            f"--mark must be PIN_MARK_BASE/0xff00 to match the entire "
            f"pinning mark range while excluding portal connections "
            f"(ct mark 0); got {argv[m_idx + 1]!r}"
        )
    finally:
        run_patcher.stop()
        pr_patcher.stop()
        nft_patcher.stop()


def test_flush_conntrack_swallows_nonzero_exit_codes():
    """conntrack returns 1 when no flows match; callers should treat
    that as a no-op success, not an error.  flush_conntrack must not
    raise in that case (nor on any other rc) — this is best-effort
    cleanup paired with a successful reconcile, and surfacing
    subprocess failures here would gate user-visible pin changes on
    a kernel state we cannot do anything about."""
    pr_patcher, _ = _make_iproute_ctx()
    nft_patcher, _ = _make_nft_ctx()
    run_patcher = patch("pinning.kernel.subprocess.run")
    run_mock = run_patcher.start()
    run_mock.return_value = MagicMock(returncode=1, stdout="", stderr="0 flow entries have been deleted.")
    try:
        rec = KernelReconciler(
            catalog=_catalog("hub"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        # MUST NOT raise:
        asyncio.run(rec.flush_conntrack("192.0.2.42"))
    finally:
        run_patcher.stop()
        pr_patcher.stop()
        nft_patcher.stop()


def test_flush_conntrack_swallows_filenotfounderror_when_binary_missing():
    """If the conntrack CLI is not installed we still want pin
    operations to succeed — the flush is a UX latency improvement,
    not a correctness requirement.  Log and move on."""
    pr_patcher, _ = _make_iproute_ctx()
    nft_patcher, _ = _make_nft_ctx()
    run_patcher = patch("pinning.kernel.subprocess.run", side_effect=FileNotFoundError())
    run_patcher.start()
    try:
        rec = KernelReconciler(
            catalog=_catalog("hub"),
            portal_addr="192.0.2.1",
            portal_port=1,
            api_port=80,
        )
        asyncio.run(rec.flush_conntrack("192.0.2.42"))
    finally:
        run_patcher.stop()
        pr_patcher.stop()
        nft_patcher.stop()


def test_reconcile_renders_includes_portal_redirect():
    """reconcile() loads nft text containing the portal redirect rule.

    Verifies the reconciler threads its portal kwargs into the
    renderer correctly and the resulting ruleset has the line we
    expect.
    """
    nft_patcher, mock_nft = _make_nft_ctx()
    try:
        rec = KernelReconciler(
            catalog=_catalog("hub"),
            portal_addr="192.0.2.7",
            portal_port=1234,
            api_port=8080,
        )
        asyncio.run(rec.reconcile({}))
        cmds = [c.args[0] for c in mock_nft.cmd.call_args_list]
        loaded = next(
            c for c in cmds
            if "table ip pinning" in c and "redirect to :8080" in c
        )
        assert "ip daddr 192.0.2.7" in loaded
        assert "tcp dport 1234" in loaded
    finally:
        nft_patcher.stop()
