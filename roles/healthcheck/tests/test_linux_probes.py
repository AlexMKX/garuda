"""
Behavioral tests for check_linux.yml — real Linux healthcheck probes.

Tests parse YAML with yaml.safe_load and verify task structure:
module names, register variables, failed_when/changed_when flags,
and command arguments — not string presence in raw file content.
"""

import yaml
import pytest
from pathlib import Path

from _hc_helpers import load_yaml

ROLE_DIR = Path(__file__).parent.parent
CHECK_LINUX_PATH = ROLE_DIR / "tasks" / "check_linux.yml"
NORMALIZE_PATH = ROLE_DIR / "tasks" / "normalize_results.yml"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _tasks_using_module(tasks: list, module_name: str) -> list[dict]:
    """Return tasks that use the given Ansible module key."""
    return [t for t in tasks if isinstance(t, dict) and module_name in t]


def _command_args(task: dict) -> str:
    """Extract the cmd string from an ansible.builtin.command task."""
    module_args = task.get("ansible.builtin.command") or task.get("command") or {}
    if isinstance(module_args, str):
        return module_args
    if isinstance(module_args, dict):
        return module_args.get("cmd", "")
    return ""


def _shell_args(task: dict) -> str:
    """Extract the cmd string from an ansible.builtin.shell task."""
    module_args = task.get("ansible.builtin.shell") or task.get("shell") or {}
    if isinstance(module_args, str):
        return module_args
    if isinstance(module_args, dict):
        return module_args.get("cmd", "")
    return ""


def _command_argv(task: dict) -> list[str]:
    """Extract argv from an ansible.builtin.command task, if present."""
    module_args = task.get("ansible.builtin.command") or task.get("command") or {}
    if isinstance(module_args, dict):
        argv = module_args.get("argv")
        if isinstance(argv, list):
            return argv
    return []


def _set_fact_key(task: dict) -> str | None:
    """Return the first fact key set by a set_fact task, or None."""
    fact_dict = task.get("ansible.builtin.set_fact") or task.get("set_fact")
    if isinstance(fact_dict, dict):
        keys = list(fact_dict.keys())
        return keys[0] if keys else None
    return None


# ---------------------------------------------------------------------------
# No stubs remain
# ---------------------------------------------------------------------------


class TestNoStubsRemain:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_LINUX_PATH)

    def test_no_not_implemented_reason(self, tasks):
        """check_linux.yml must not contain 'not_implemented' as a reason value."""
        task_text = yaml.dump(tasks)
        assert "not_implemented" not in task_text, (
            "Stub 'not_implemented' reason found — stubs must be replaced"
        )

    def test_no_stub_status_value(self, tasks):
        """check_linux.yml must not use literal 'stub' as a status value."""
        task_text = yaml.dump(tasks)
        assert "stub" not in task_text.lower().split(), (
            "Stub 'stub' status found — stubs must be replaced"
        )

    def test_no_stub_task_names(self, tasks):
        """No task in check_linux.yml may have a name containing 'Stub'."""
        for task in tasks:
            if isinstance(task, dict):
                name = task.get("name", "")
                assert "Stub" not in name, f"Stub task found: {name!r}"


# ---------------------------------------------------------------------------
# Linux probe does NOT use peer_checks
# ---------------------------------------------------------------------------


class TestNoPeerChecksOnLinux:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_LINUX_PATH)

    def test_linux_probe_does_not_use_peer_checks(self, tasks):
        """check_linux.yml must not reference healthcheck_peer_checks at all."""
        assert all("healthcheck_peer_checks" not in str(task) for task in tasks), (
            "Linux probe must not use healthcheck_peer_checks — peer probing removed"
        )

    def test_no_wg_show_tunnel_probe(self, tasks):
        """check_linux.yml must not probe tunnel interfaces via 'wg show tunnel-*'."""
        rendered = yaml.safe_dump(tasks)
        assert "wg show tunnel-" not in rendered, (
            "Linux probe must not use 'wg show tunnel-*' — WG peer probing removed"
        )

    def test_no_ip_link_show_tunnel_probe(self, tasks):
        """check_linux.yml must not probe tunnel interfaces via 'ip link show tunnel-*'."""
        rendered = yaml.safe_dump(tasks)
        assert "ip link show tunnel-" not in rendered, (
            "Linux probe must not use 'ip link show tunnel-*' — tunnel interface probing removed"
        )

    def test_no_ping_peer_probe(self, tasks):
        """check_linux.yml must not use ping-based peer IP probing."""
        command_tasks = _tasks_using_module(
            tasks, "ansible.builtin.command"
        ) + _tasks_using_module(tasks, "command")
        ping_tasks = [t for t in command_tasks if "ping" in _command_args(t)]
        assert len(ping_tasks) == 0, (
            "Linux probe must not use ping for peer probing — removed from this path"
        )


# ---------------------------------------------------------------------------
# OSPF neighbor probe: container runtime, not host vtysh
# ---------------------------------------------------------------------------


class TestOspfProbes:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_LINUX_PATH)

    def test_ospf_probe_uses_container_runtime_not_host_vtysh(self, tasks):
        """OSPF probe must run via docker compose/exec, not host-level vtysh."""
        rendered = yaml.safe_dump(tasks)
        assert "docker compose" in rendered or "docker exec" in rendered, (
            "OSPF probe must use docker compose or docker exec (container runtime)"
        )
        assert "command -v vtysh" not in rendered, (
            "OSPF probe must not check for host-level vtysh"
        )

    def test_ospf_probe_does_not_invoke_bare_host_vtysh(self, tasks):
        """OSPF probe must not invoke bare vtysh on the host (only inside container)."""
        shell_tasks = _tasks_using_module(
            tasks, "ansible.builtin.shell"
        ) + _tasks_using_module(tasks, "shell")
        bare_vtysh_tasks = [
            t
            for t in shell_tasks
            if "vtysh" in _shell_args(t) and "docker" not in _shell_args(t)
        ]
        assert len(bare_vtysh_tasks) == 0, (
            "OSPF probe must not use bare host-level vtysh — must go through container runtime"
        )

    def test_ospf_probe_uses_shell_for_runtime_resolution(self, tasks):
        """OSPF probe uses shell because container id resolution needs shell substitution."""
        shell_tasks = _tasks_using_module(
            tasks, "ansible.builtin.shell"
        ) + _tasks_using_module(tasks, "shell")
        matching_tasks = [
            t
            for t in shell_tasks
            if "docker exec" in _shell_args(t) and "vtysh" in _shell_args(t)
        ]
        assert matching_tasks, (
            "OSPF probe must use shell-based docker exec so runtime resolution works"
        )

    def test_ospf_probe_has_failed_when_false(self, tasks):
        """OSPF probe tasks must have failed_when: false."""
        exec_tasks = (
            _tasks_using_module(tasks, "ansible.builtin.command")
            + _tasks_using_module(tasks, "command")
            + _tasks_using_module(tasks, "ansible.builtin.shell")
            + _tasks_using_module(tasks, "shell")
        )
        ospf_tasks = [
            t
            for t in exec_tasks
            if "ospf" in str(t).lower() or "vtysh" in _command_args(t) + _shell_args(t)
        ]
        assert len(ospf_tasks) >= 1, "No OSPF probe exec tasks found"
        for t in ospf_tasks:
            assert t.get("failed_when") is False, (
                f"OSPF probe task {t.get('name')!r} must have failed_when: false"
            )

    def test_ospf_results_fact_is_set(self, tasks):
        """check_linux.yml must set _hc_raw_ospf_results via set_fact."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        ospf_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_ospf_results"
        ]
        assert len(ospf_facts) >= 1, (
            "check_linux.yml must set _hc_raw_ospf_results via set_fact"
        )

    def test_ospf_full_state_maps_to_ok(self, tasks):
        """OSPF normalization logic must check for 'Full' neighbor state to produce 'ok'."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        ospf_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_ospf_results"
        ]
        assert len(ospf_facts) >= 1
        ospf_template = yaml.dump(ospf_facts)
        assert "Full" in ospf_template, (
            "OSPF normalization must check for 'Full' neighbor state to produce 'ok'"
        )


# ---------------------------------------------------------------------------
# Container probe: substack-driven, not single-container name guessing
# ---------------------------------------------------------------------------


class TestContainerProbes:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_LINUX_PATH)

    def test_container_probe_uses_substack_input_variable(self, tasks):
        """Container probe must iterate healthcheck_container_substacks, not container_checks."""
        rendered = yaml.safe_dump(tasks)
        assert "healthcheck_container_substacks" in rendered, (
            "Container probe must use healthcheck_container_substacks as its input variable"
        )
        assert "healthcheck_container_checks" not in rendered, (
            "Container probe must not use old healthcheck_container_checks variable"
        )

    def test_container_probe_uses_docker_ps_or_inspect_via_exec(self, tasks):
        """Container checks must use docker ps or docker inspect (substack-based)."""
        rendered = yaml.safe_dump(tasks)
        assert "docker ps" in rendered or "docker inspect" in rendered, (
            "check_linux.yml must use 'docker ps' or 'docker inspect' for container checks"
        )

    def test_container_probe_uses_argv_for_json_format(self, tasks):
        """Container discovery must pass the Docker JSON format as one argv item."""
        command_tasks = _tasks_using_module(
            tasks, "ansible.builtin.command"
        ) + _tasks_using_module(tasks, "command")
        docker_ps_tasks = [
            t for t in command_tasks if _command_argv(t)[:3] == ["docker", "ps", "-a"]
        ]
        assert docker_ps_tasks, "Expected docker ps container discovery task using argv"
        argv = _command_argv(docker_ps_tasks[0])
        assert "--format" in argv, "docker ps probe must pass --format explicitly"
        fmt = argv[argv.index("--format") + 1]
        assert "json ." in fmt and len(fmt.split()) >= 2, (
            "docker ps probe must keep the Docker JSON template as one argv item to avoid split-arg bugs"
        )

    def test_container_probe_has_failed_when_false(self, tasks):
        """Container probe exec tasks must have failed_when: false."""
        exec_tasks = (
            _tasks_using_module(tasks, "ansible.builtin.command")
            + _tasks_using_module(tasks, "command")
            + _tasks_using_module(tasks, "ansible.builtin.shell")
            + _tasks_using_module(tasks, "shell")
        )
        container_tasks = [
            t
            for t in exec_tasks
            if "docker"
            in (_command_args(t) + _shell_args(t) + " ".join(_command_argv(t)))
            and "ospf" not in str(t).lower()
            and "vtysh"
            not in (_command_args(t) + _shell_args(t) + " ".join(_command_argv(t)))
        ]
        assert len(container_tasks) >= 1, "No container probe exec tasks found"
        for t in container_tasks:
            assert t.get("failed_when") is False, (
                f"Container probe task {t.get('name')!r} must have failed_when: false"
            )

    def test_container_results_fact_is_set(self, tasks):
        """check_linux.yml must set _hc_raw_container_results via set_fact."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        container_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_container_results"
        ]
        assert len(container_facts) >= 1, (
            "check_linux.yml must set _hc_raw_container_results via set_fact"
        )

    def test_container_normalization_checks_running_state(self, tasks):
        """Container normalization must check for 'running' container state."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        container_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_container_results"
        ]
        assert len(container_facts) >= 1
        template_text = yaml.dump(container_facts)
        assert "running" in template_text, (
            "Container normalization must check 'running' state"
        )

    def test_container_normalization_checks_healthy_state(self, tasks):
        """Container normalization must check for 'healthy' health status."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        container_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_container_results"
        ]
        assert len(container_facts) >= 1
        template_text = yaml.dump(container_facts)
        assert "healthy" in template_text, (
            "Container normalization must check 'healthy' health status"
        )


# ---------------------------------------------------------------------------
# Result shape preservation
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


class TestResultShapePreservation:
    @pytest.fixture
    def normalize_tasks(self):
        return load_yaml(NORMALIZE_PATH)

    @pytest.fixture
    def linux_tasks(self):
        return load_yaml(CHECK_LINUX_PATH)

    def test_normalize_still_has_all_required_keys(self, normalize_tasks):
        """normalize_results.yml must reference all required result keys."""
        task_text = yaml.dump(normalize_tasks)
        for key in REQUIRED_RESULT_KEYS:
            assert key in task_text, (
                f"normalize_results.yml must reference '{key}' in result shape"
            )

    def test_normalize_merges_linux_ospf_and_container_results(self, normalize_tasks):
        """normalize_results.yml must merge Linux OSPF and container/substack results."""
        task_text = yaml.dump(normalize_tasks)
        assert "_hc_raw_ospf_results" in task_text, (
            "normalize_results.yml must merge _hc_raw_ospf_results"
        )
        assert "_hc_raw_container_results" in task_text, (
            "normalize_results.yml must merge _hc_raw_container_results"
        )

    def test_linux_probe_does_not_set_peer_results_fact(self, linux_tasks):
        """check_linux.yml must not set _hc_raw_peer_results — peer probing removed from Linux path."""
        set_fact_tasks = _tasks_using_module(
            linux_tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(linux_tasks, "set_fact")
        peer_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_peer_results"
        ]
        assert len(peer_facts) == 0, (
            "check_linux.yml must not set _hc_raw_peer_results — Linux peer probing removed"
        )

    def test_ospf_results_have_check_type_ospf(self, linux_tasks):
        """OSPF set_fact template must include check_type: ospf."""
        set_fact_tasks = _tasks_using_module(
            linux_tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(linux_tasks, "set_fact")
        ospf_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_ospf_results"
        ]
        assert len(ospf_facts) >= 1
        template_text = yaml.dump(ospf_facts)
        assert "check_type" in template_text
        assert "ospf" in template_text

    def test_container_results_have_check_type_container(self, linux_tasks):
        """Container set_fact template must include check_type: container."""
        set_fact_tasks = _tasks_using_module(
            linux_tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(linux_tasks, "set_fact")
        container_facts = [
            t for t in set_fact_tasks if _set_fact_key(t) == "_hc_raw_container_results"
        ]
        assert len(container_facts) >= 1
        template_text = yaml.dump(container_facts)
        assert "check_type" in template_text
        assert "container" in template_text

    def test_all_results_have_platform_linux(self, linux_tasks):
        """All result set_facts in check_linux.yml must include platform: linux."""
        set_fact_tasks = _tasks_using_module(
            linux_tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(linux_tasks, "set_fact")
        result_facts = [
            t
            for t in set_fact_tasks
            if _set_fact_key(t)
            in (
                "_hc_raw_ospf_results",
                "_hc_raw_container_results",
            )
        ]
        assert len(result_facts) >= 1
        template_text = yaml.dump(result_facts)
        assert "linux" in template_text, (
            "All check_linux.yml results must set platform: linux"
        )


# ---------------------------------------------------------------------------
# Non-fatal failure capture
# ---------------------------------------------------------------------------


class TestNonFatalFailureCapture:
    @pytest.fixture
    def tasks(self):
        return load_yaml(CHECK_LINUX_PATH)

    def test_probe_tasks_use_changed_when_false(self, tasks):
        """All exec probe tasks must be marked changed_when: false (read-only)."""
        exec_tasks = (
            _tasks_using_module(tasks, "ansible.builtin.command")
            + _tasks_using_module(tasks, "command")
            + _tasks_using_module(tasks, "ansible.builtin.shell")
            + _tasks_using_module(tasks, "shell")
        )
        assert len(exec_tasks) >= 1, "No probe exec tasks found"
        for t in exec_tasks:
            assert t.get("changed_when") is False, (
                f"Probe task {t.get('name')!r} must have changed_when: false"
            )

    def test_fail_status_produced_in_templates(self, tasks):
        """Normalization templates must produce 'fail' status for probe failures."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        result_facts = [
            t
            for t in set_fact_tasks
            if _set_fact_key(t)
            in (
                "_hc_raw_ospf_results",
                "_hc_raw_container_results",
            )
        ]
        template_text = yaml.dump(result_facts)
        assert "fail" in template_text, (
            "Normalization templates must produce 'fail' status for probe failures"
        )

    def test_ok_status_produced_in_templates(self, tasks):
        """Normalization templates must produce 'ok' status for successful probes."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        result_facts = [
            t
            for t in set_fact_tasks
            if _set_fact_key(t)
            in (
                "_hc_raw_ospf_results",
                "_hc_raw_container_results",
            )
        ]
        template_text = yaml.dump(result_facts)
        assert "ok" in template_text, (
            "Normalization templates must produce 'ok' status for successful probes"
        )

    def test_warn_status_produced_in_templates(self, tasks):
        """Normalization templates must produce 'warn' status for unavailable tools."""
        set_fact_tasks = _tasks_using_module(
            tasks, "ansible.builtin.set_fact"
        ) + _tasks_using_module(tasks, "set_fact")
        result_facts = [
            t
            for t in set_fact_tasks
            if _set_fact_key(t)
            in (
                "_hc_raw_ospf_results",
                "_hc_raw_container_results",
            )
        ]
        template_text = yaml.dump(result_facts)
        assert "warn" in template_text, (
            "Normalization templates must produce 'warn' status for indeterminate cases"
        )
