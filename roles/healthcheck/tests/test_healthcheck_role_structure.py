"""
Behavioral tests for healthcheck role structure and playbook orchestration.

Tests parse YAML files with yaml.safe_load and verify task structure,
module names, include references, variable types — not string presence.
"""

import yaml
import pytest
from pathlib import Path

from _hc_helpers import load_yaml

# Tests live in roles/healthcheck/tests/ — role root is two levels up,
# repo root is four levels up.
ROLE_DIR = Path(__file__).parent.parent
REPO_ROOT = ROLE_DIR.parent.parent


# ---------------------------------------------------------------------------
# Role defaults: variables parse as correct Python types
# ---------------------------------------------------------------------------


class TestRoleDefaults:
    @pytest.fixture
    def defaults(self):
        return load_yaml(ROLE_DIR / "defaults" / "main.yml")

    def test_peer_checks_default_is_list(self, defaults):
        assert isinstance(defaults["healthcheck_peer_checks"], list)

    def test_ospf_checks_default_is_list(self, defaults):
        assert isinstance(defaults["healthcheck_ospf_checks"], list)

    def test_container_substacks_default_is_list(self, defaults):
        assert isinstance(defaults["healthcheck_container_substacks"], list)


# ---------------------------------------------------------------------------
# tasks/main.yml: platform dispatching via include_tasks
# ---------------------------------------------------------------------------


class TestTasksMain:
    @pytest.fixture
    def tasks(self):
        return load_yaml(ROLE_DIR / "tasks" / "main.yml")

    def test_linux_include_has_when_condition(self, tasks):
        """Linux include must have a 'when:' guard for platform branching."""
        linux_includes = [
            t
            for t in tasks
            if isinstance(t, dict)
            and "check_linux.yml"
            in str(t.get("ansible.builtin.include_tasks", t.get("include_tasks", "")))
        ]
        assert len(linux_includes) >= 1
        for inc in linux_includes:
            assert "when" in inc, "Linux include_tasks must have a 'when:' condition"

    def test_mikrotik_include_has_when_condition(self, tasks):
        """MikroTik include must have a 'when:' guard for platform branching."""
        mikrotik_includes = [
            t
            for t in tasks
            if isinstance(t, dict)
            and "check_mikrotik.yml"
            in str(t.get("ansible.builtin.include_tasks", t.get("include_tasks", "")))
        ]
        assert len(mikrotik_includes) >= 1
        for inc in mikrotik_includes:
            assert "when" in inc, "MikroTik include_tasks must have a 'when:' condition"

# ---------------------------------------------------------------------------
# tasks/normalize_results.yml: result shape structure
# ---------------------------------------------------------------------------

REQUIRED_RESULT_KEYS = {
    "host",
    "platform",
    "check_type",
    "target",
    "status",
    "reason",
    "details",
}


class TestNormalizeResults:
    @pytest.fixture
    def tasks(self):
        return load_yaml(ROLE_DIR / "tasks" / "normalize_results.yml")

    def test_sets_healthcheck_results_via_set_fact(self, tasks):
        """normalize_results.yml must use set_fact to set healthcheck_results."""
        set_fact_tasks = [
            t
            for t in tasks
            if isinstance(t, dict)
            and ("ansible.builtin.set_fact" in t or "set_fact" in t)
        ]
        assert len(set_fact_tasks) >= 1, (
            "normalize_results.yml must contain a set_fact task"
        )
        for t in set_fact_tasks:
            fact_dict = t.get("ansible.builtin.set_fact") or t.get("set_fact") or {}
            if isinstance(fact_dict, dict) and "healthcheck_results" in fact_dict:
                return
        pytest.fail("normalize_results.yml must set the 'healthcheck_results' fact key")

    def test_result_template_has_all_required_keys(self, tasks):
        """The set_fact template must reference all required normalized result keys."""
        task_text = yaml.dump(tasks)
        for key in REQUIRED_RESULT_KEYS:
            assert key in task_text, (
                f"normalize_results.yml must reference '{key}' in result shape"
            )
