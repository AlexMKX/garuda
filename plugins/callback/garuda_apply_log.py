"""
garuda_apply_log — Ansible callback that emits one plain-text line per task
to the file specified by GARUDA_APPLY_LOG_PATH.

Line format:
    2026-04-29T22:14:03Z HOST STATUS<padded 11> | TASK_NAME

Status values: OK, CHANGED, SKIP, FAIL, UNREACHABLE.

Activated by a wrapping shell script (modules/linux_apply/files/run_linux_apply.sh)
which sets:
    ANSIBLE_CALLBACK_PLUGINS=<repo_root>/plugins/callback
    ANSIBLE_CALLBACKS_ENABLED=garuda_apply_log
    GARUDA_APPLY_LOG_PATH=<tmp>/apply.log

The shell script reads the resulting file after ansible exits and embeds it
into the linux_apply result.json envelope as `apply_log`.
"""

from __future__ import annotations

import datetime
import os

from ansible.plugins.callback import CallbackBase

DOCUMENTATION = """
    name: garuda_apply_log
    type: notification
    short_description: Plain-text per-task log for linux_apply.
    description:
        - Writes one ISO8601-prefixed line per task to GARUDA_APPLY_LOG_PATH.
        - No-ops when the env var is unset (defensive — production callers
          always set it).
    requirements:
        - ANSIBLE_CALLBACKS_ENABLED contains 'garuda_apply_log'
"""

_STATUS_WIDTH = 11  # accommodates "UNREACHABLE"


def _now_iso() -> str:
    """UTC timestamp with second precision and Z suffix."""
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def _host_name(result) -> str:
    host = getattr(result, "_host", None)
    if host is None:
        return "?"
    name = getattr(host, "name", None)
    if name:
        return name
    get_name = getattr(host, "get_name", None)
    if callable(get_name):
        return get_name()
    return "?"


def _task_name(result) -> str:
    task = getattr(result, "_task", None)
    if task is None:
        return "?"
    get_name = getattr(task, "get_name", None)
    if callable(get_name):
        return get_name() or "?"
    name = getattr(task, "name", None)
    return name or "?"


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "garuda_apply_log"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._path = os.environ.get("GARUDA_APPLY_LOG_PATH") or None

    def _emit(self, status: str, result) -> None:
        if not self._path:
            return
        line = "{ts} {host} {status:<{w}} | {task}\n".format(
            ts=_now_iso(),
            host=_host_name(result),
            status=status,
            w=_STATUS_WIDTH,
            task=_task_name(result),
        )
        # Append; failures here would mask ansible failures, so tolerate
        # IO errors silently rather than raising.
        try:
            with open(self._path, "a", encoding="utf-8") as fh:
                fh.write(line)
        except OSError:
            pass

    # ── Ansible callback hooks ────────────────────────────────────────────
    def v2_runner_on_ok(self, result):
        is_changed = False
        try:
            is_changed = bool(result.is_changed())
        except Exception:
            is_changed = bool(getattr(result, "_result", {}).get("changed"))
        self._emit("CHANGED" if is_changed else "OK", result)

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._emit("FAIL", result)

    def v2_runner_on_skipped(self, result):
        self._emit("SKIP", result)

    def v2_runner_on_unreachable(self, result):
        self._emit("UNREACHABLE", result)
