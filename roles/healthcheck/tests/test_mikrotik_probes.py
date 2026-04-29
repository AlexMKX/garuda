"""
Behavioral tests for check_mikrotik.yml — real MikroTik RouterOS API probes.

Tests parse YAML with yaml.safe_load and verify task structure:
module names, module_defaults configuration, delegate_to, register variables,
failed_when/changed_when flags — not string presence in raw file content.
"""

import yaml
import pytest
from pathlib import Path

from _hc_helpers import load_yaml

ROLE_DIR = Path(__file__).parent.parent
CHECK_MIKROTIK_PATH = ROLE_DIR / "tasks" / "check_mikrotik.yml"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _tasks_using_module(tasks: list, module_name: str) -> list[dict]:
    """Return tasks that use the given Ansible module key (top-level only)."""
    return [t for t in tasks if isinstance(t, dict) and module_name in t]


def _set_fact_key(task: dict) -> str | None:
    """Return the first fact key set by a set_fact task, or None."""
    fact_dict = task.get("ansible.builtin.set_fact") or task.get("set_fact")
    if isinstance(fact_dict, dict):
        keys = list(fact_dict.keys())
        return keys[0] if keys else None
    return None


def _collect_block_tasks(tasks: list) -> list[dict]:
    """Recursively collect tasks from block/rescue/always sections."""
    result = []
    for task in tasks:
        if not isinstance(task, dict):
            continue
        result.append(task)
        for section in ("block", "rescue", "always"):
            inner = task.get(section, []) or []
            result.extend(_collect_block_tasks(inner))
    return result


# ---------------------------------------------------------------------------
# No stubs remain
# ---------------------------------------------------------------------------


class TestNoStubsRemain:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_MIKROTIK_PATH)

    def test_no_not_implemented_reason(self, tasks):
        """check_mikrotik.yml must not contain 'not_implemented' as a reason value."""
        task_text = yaml.dump(tasks)
        assert "not_implemented" not in task_text, (
            "Stub 'not_implemented' reason found — stubs must be replaced"
        )

    def test_no_stub_status_value(self, tasks):
        """check_mikrotik.yml must not use literal 'stub' as a status value."""
        task_text = yaml.dump(tasks)
        assert "stub" not in task_text.lower().split(), (
            "Stub 'stub' status found — stubs must be replaced"
        )

    def test_no_stub_task_names(self, tasks):
        """No task in check_mikrotik.yml may have a name containing 'Stub'."""
        for task in _collect_block_tasks(tasks):
            name = task.get("name", "")
            assert "Stub" not in name, f"Stub task found: {name!r}"


# ---------------------------------------------------------------------------
# RouterOS API usage: module, paths, delegation
# ---------------------------------------------------------------------------


class TestRouterOSApiUsage:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_MIKROTIK_PATH)

    @pytest.fixture
    def all_tasks(self, tasks):
        """Flat list including tasks inside block/rescue/always."""
        return _collect_block_tasks(tasks)

    def test_uses_community_routeros_api_module(self, all_tasks):
        """check_mikrotik.yml must use community.routeros.api for probes."""
        api_tasks = _tasks_using_module(all_tasks, "community.routeros.api")
        assert len(api_tasks) >= 1, (
            "check_mikrotik.yml must use community.routeros.api module"
        )

    def test_queries_wireguard_interface_path(self, all_tasks):
        """check_mikrotik.yml must query 'interface wireguard' path."""
        api_tasks = _tasks_using_module(all_tasks, "community.routeros.api")
        iface_tasks = [
            t
            for t in api_tasks
            if t.get("community.routeros.api", {}).get("path") == "interface wireguard"
        ]
        assert len(iface_tasks) >= 1, (
            "check_mikrotik.yml must query path 'interface wireguard' for interface state"
        )

    def test_queries_wireguard_peers_path(self, all_tasks):
        """check_mikrotik.yml must query 'interface wireguard peers' path."""
        api_tasks = _tasks_using_module(all_tasks, "community.routeros.api")
        peer_tasks = [
            t
            for t in api_tasks
            if t.get("community.routeros.api", {}).get("path")
            == "interface wireguard peers"
        ]
        assert len(peer_tasks) >= 1, (
            "check_mikrotik.yml must query path 'interface wireguard peers' for peer presence"
        )

    def test_queries_ospf_neighbor_path(self, all_tasks):
        """check_mikrotik.yml must query OSPF neighbor path via RouterOS API."""
        api_tasks = _tasks_using_module(all_tasks, "community.routeros.api")
        ospf_tasks = [
            t
            for t in api_tasks
            if "ospf" in t.get("community.routeros.api", {}).get("path", "").lower()
            and "neighbor"
            in t.get("community.routeros.api", {}).get("path", "").lower()
        ]
        assert len(ospf_tasks) >= 1, (
            "check_mikrotik.yml must query OSPF neighbor path via RouterOS API"
        )

    def test_api_calls_delegated_to_localhost(self, tasks):
        """RouterOS API block must be delegated to localhost."""
        # The delegation is on the outer block task, not the inner api tasks
        block_tasks = [t for t in tasks if isinstance(t, dict) and "block" in t]
        assert len(block_tasks) >= 1, (
            "check_mikrotik.yml must use a block for API calls"
        )
        for bt in block_tasks:
            assert bt.get("delegate_to") == "localhost", (
                f"Block task must have delegate_to: localhost, got: {bt.get('delegate_to')!r}"
            )

    def test_uses_module_defaults_block(self, tasks):
        """Connection params must be declared once via module_defaults on the block task."""
        block_tasks = [t for t in tasks if isinstance(t, dict) and "block" in t]
        assert len(block_tasks) >= 1
        for bt in block_tasks:
            assert "module_defaults" in bt, (
                "Block task must have module_defaults to avoid repeating credentials"
            )

    def test_validate_certs_defaults_to_true(self, tasks):
        """validate_certs must default to true, not false, matching security policy."""
        block_tasks = [
            t for t in tasks if isinstance(t, dict) and "module_defaults" in t
        ]
        assert len(block_tasks) >= 1, (
            "check_mikrotik.yml must set validate_certs inside module_defaults"
        )
        found_validate_certs = False
        for task in block_tasks:
            md = task.get("module_defaults", {})
            for group_val in md.values():
                if isinstance(group_val, dict) and "validate_certs" in group_val:
                    found_validate_certs = True
                    val = str(group_val["validate_certs"])
                    assert "default(true)" in val, (
                        f"validate_certs must use default(true), got: {val!r}"
                    )
                    assert "default(false)" not in val, (
                        f"validate_certs must not use default(false), got: {val!r}"
                    )
        assert found_validate_certs, (
            "check_mikrotik.yml must set validate_certs inside module_defaults"
        )

    def test_no_hardcoded_admin_credential_fallback(self, tasks):
        """Credentials must not fall back to hardcoded 'admin' or empty string."""
        task_text = yaml.dump(tasks)
        assert (
            "default('admin')" not in task_text and 'default("admin")' not in task_text
        ), "check_mikrotik.yml must not use hardcoded 'admin' credential fallback"
        assert "default('')" not in task_text and 'default("")' not in task_text, (
            "check_mikrotik.yml must not use hardcoded empty-string password fallback"
        )


# ---------------------------------------------------------------------------
# Non-fatal capture
# ---------------------------------------------------------------------------


class TestNonFatalCapture:
    @pytest.fixture
    def all_tasks(self):
        return _collect_block_tasks(load_yaml(CHECK_MIKROTIK_PATH))

    def test_api_probe_tasks_have_failed_when_false(self, all_tasks):
        """RouterOS API probe tasks must have failed_when: false."""
        api_tasks = _tasks_using_module(all_tasks, "community.routeros.api")
        assert len(api_tasks) >= 1, "No community.routeros.api tasks found"
        for t in api_tasks:
            assert t.get("failed_when") is False, (
                f"API task {t.get('name')!r} must have failed_when: false"
            )

    def test_api_probe_tasks_have_changed_when_false(self, all_tasks):
        """RouterOS API probe tasks must have changed_when: false (read-only)."""
        api_tasks = _tasks_using_module(all_tasks, "community.routeros.api")
        assert len(api_tasks) >= 1
        for t in api_tasks:
            assert t.get("changed_when") is False, (
                f"API task {t.get('name')!r} must have changed_when: false"
            )


# ---------------------------------------------------------------------------
# Normalized result shape
# ---------------------------------------------------------------------------


class TestNormalizedResultShape:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_MIKROTIK_PATH)

    def test_sets_peer_results_fact(self, tasks):
        """check_mikrotik.yml must set _hc_raw_peer_results via set_fact."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        peer_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_peer_results"
        ]
        assert len(peer_facts) >= 1, (
            "check_mikrotik.yml must set _hc_raw_peer_results via set_fact"
        )

    def test_sets_ospf_results_fact(self, tasks):
        """check_mikrotik.yml must set _hc_raw_ospf_results via set_fact."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        ospf_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_ospf_results"
        ]
        assert len(ospf_facts) >= 1, (
            "check_mikrotik.yml must set _hc_raw_ospf_results via set_fact"
        )

    def test_sets_container_results_as_empty_list(self, tasks):
        """check_mikrotik.yml must set _hc_raw_container_results (empty list)."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        container_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_container_results"
        ]
        assert len(container_facts) >= 1, (
            "check_mikrotik.yml must set _hc_raw_container_results via set_fact"
        )
        # Verify it's actually set to an empty list (no containers on MikroTik)
        fact_dict = (
            container_facts[0].get("ansible.builtin.set_fact")
            or container_facts[0].get("set_fact")
            or {}
        )
        assert fact_dict.get("_hc_raw_container_results") == [], (
            "MikroTik container results must be an empty list"
        )

    def test_peer_results_include_platform_mikrotik(self, tasks):
        """Peer set_fact template must set platform: mikrotik."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        peer_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_peer_results"
        ]
        assert len(peer_facts) >= 1
        template_text = yaml.dump(peer_facts)
        assert "mikrotik" in template_text, "Peer results must set platform: mikrotik"

    def test_peer_results_include_check_type_peer(self, tasks):
        """Peer set_fact template must include check_type: peer."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        peer_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_peer_results"
        ]
        assert len(peer_facts) >= 1
        template_text = yaml.dump(peer_facts)
        assert "check_type" in template_text
        assert "peer" in template_text

    def test_ospf_results_include_check_type_ospf(self, tasks):
        """OSPF set_fact template must include check_type: ospf."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        ospf_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_ospf_results"
        ]
        assert len(ospf_facts) >= 1
        template_text = yaml.dump(ospf_facts)
        assert "check_type" in template_text
        assert "ospf" in template_text

    def test_result_includes_required_keys(self, tasks):
        """Result dicts must include all required normalized keys."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        result_facts = [
            t
            for t in set_fact_tasks
            if _set_fact_key(t) in ("_hc_raw_peer_results", "_hc_raw_ospf_results")
        ]
        assert len(result_facts) >= 1
        template_text = yaml.dump(result_facts)
        for key in ("target", "status", "reason", "details", "tunnel"):
            assert key in template_text, (
                f"check_mikrotik.yml must include '{key}' in result"
            )


# ---------------------------------------------------------------------------
# Status mapping
# ---------------------------------------------------------------------------


class TestStatusMapping:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_MIKROTIK_PATH)

    def test_ok_status_produced(self, tasks):
        """check_mikrotik.yml must produce 'ok' status for successful probes."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        result_facts = [
            t
            for t in set_fact_tasks
            if _set_fact_key(t) in ("_hc_raw_peer_results", "_hc_raw_ospf_results")
        ]
        template_text = yaml.dump(result_facts)
        assert "ok" in template_text, "check_mikrotik.yml must produce 'ok' status"

    def test_fail_status_produced(self, tasks):
        """check_mikrotik.yml must produce 'fail' status for probe failures."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        result_facts = [
            t
            for t in set_fact_tasks
            if _set_fact_key(t) in ("_hc_raw_peer_results", "_hc_raw_ospf_results")
        ]
        template_text = yaml.dump(result_facts)
        assert "fail" in template_text, "check_mikrotik.yml must produce 'fail' status"

    def test_warn_status_produced(self, tasks):
        """check_mikrotik.yml must produce 'warn' status for indeterminate cases."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        result_facts = [
            t
            for t in set_fact_tasks
            if _set_fact_key(t) in ("_hc_raw_peer_results", "_hc_raw_ospf_results")
        ]
        template_text = yaml.dump(result_facts)
        assert "warn" in template_text, "check_mikrotik.yml must produce 'warn' status"

    def test_ospf_full_state_maps_to_ok(self, tasks):
        """OSPF 'full' neighbor state must map to 'ok' status."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        ospf_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_ospf_results"
        ]
        assert len(ospf_facts) >= 1
        template_text = yaml.dump(ospf_facts)
        assert "full" in template_text.lower(), (
            "check_mikrotik.yml must check for 'full' OSPF neighbor state to produce 'ok'"
        )
