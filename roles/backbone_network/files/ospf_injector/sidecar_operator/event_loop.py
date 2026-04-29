"""Signal handling and event polling mixin for SidecarOperator.

Extracted from runtime.py to keep the main reconciliation class focused on
reconcile logic. Mixed into SidecarOperator via multiple inheritance.
"""

from __future__ import annotations

import logging
import signal
import time

logger = logging.getLogger(__name__)


# Container-scoped event actions that indicate a state change the reconciler
# must react to. Anything outside this set (notably ``exec_*``, ``attach``,
# ``top``, ``resize``) is ignored because the operator itself performs exec
# during reconcile (e.g. FRRConsumer.on_reconcile → list_workload_interfaces)
# and docker-compose healthchecks perform exec on a fixed schedule. Allowing
# those events to wake the reconciler creates a self-triggering hot loop that
# pins CPU and spams the Docker daemon.
_LIFECYCLE_ACTIONS: frozenset[str] = frozenset(
    {
        "create",
        "start",
        "die",
        "stop",
        "kill",
        "restart",
        "destroy",
        "pause",
        "unpause",
        "health_status",
        "oom",
        "rename",
    }
)


class EventLoopMixin:
    """Mixin providing signal handling and Docker event polling.

    Requires the host class to provide:
      - self.reconcile_requested (bool, settable)
      - self.shutdown_requested (bool, readable)
      - self.config.reconcile_interval (float)
      - self._last_poll_time (float, settable)
      - self.client (docker.DockerClient)
      - self.request_shutdown(signal_name: str) method
    """

    def _install_signal_handlers(self) -> None:
        """Register SIGTERM, SIGINT, and SIGHUP to request graceful shutdown."""
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(
                sig,
                lambda _signum, _frame, _sig=sig: self.request_shutdown(
                    signal_name=_sig.name
                ),
            )

    def _sleep_until_next_interval(self) -> None:
        """Sleep for the configured reconcile interval, waking early on events.

        Returns immediately if reconcile_requested is already set. Otherwise
        sleeps for the configured interval, checking every second for an early
        wakeup via reconcile_requested or shutdown_requested. Clears
        reconcile_requested before returning so the next pass starts clean.
        """
        if self.reconcile_requested:
            self.reconcile_requested = False
            return

        deadline = time.monotonic() + self.config.reconcile_interval
        while time.monotonic() < deadline:
            if self.reconcile_requested or self.shutdown_requested:
                break
            time.sleep(min(1.0, deadline - time.monotonic()))

        self.reconcile_requested = False

    def _poll_events_once(self) -> None:
        """Consume Docker events from the last poll window (bounded by wall clock).

        Opens a fresh bounded event query (since last poll, until now) so the
        for-loop always terminates. Sets reconcile_requested=True only for
        container lifecycle events (see ``_LIFECYCLE_ACTIONS``). Exec and
        attach events are intentionally ignored because they are generated
        by the operator's own exec calls and by docker-compose healthchecks,
        and letting them wake the reconciler causes a self-triggering hot
        loop.
        """
        now = time.time()
        since = self._last_poll_time
        self._last_poll_time = now
        try:
            for event in self.client.events(decode=True, since=since, until=now):
                if not isinstance(event, dict):
                    continue
                if event.get("Type") != "container":
                    continue
                # Docker serialises some actions with a free-form suffix
                # (``exec_create: <cmd>``, ``health_status: healthy``).  Strip
                # everything after the first colon to get the action keyword.
                raw_action = event.get("Action") or ""
                action = raw_action.split(":", 1)[0].strip()
                if action in _LIFECYCLE_ACTIONS:
                    logger.debug(
                        "docker container lifecycle event: action=%s", raw_action
                    )
                    self.reconcile_requested = True
        except Exception:  # noqa: BLE001 — docker event polling must not crash operator
            logger.warning("error polling Docker events", exc_info=True)

    def _close_event_stream(self) -> None:
        """No-op: event streams are opened per-poll and self-closing."""
