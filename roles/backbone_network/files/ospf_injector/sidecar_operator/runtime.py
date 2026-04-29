"""Runtime loop and orchestration for the generic sidecar operator.

The SidecarOperator drives the reconciliation loop: it discovers target
containers and managed sidecars, invokes consumer hooks in the correct order,
and executes create/replace/remove actions via docker_api helpers.

Hook ordering contract:
- on_reconcile()        — fires before any lifecycle action for the pair
- before_sidecar_stopped() — fires before every remove (orphan, target_died, replace)
- on_sidecar_started()  — fires after a successful create or replace

Failure handling:
- on_reconcile() failure for a pair → skip actions for that pair; continue others
- before_sidecar_stopped() failure → log warning; sidecar removed unconditionally
- Docker connectivity failure → propagates up (process-fatal)

Shutdown:
- SIGTERM, SIGINT, SIGHUP all set shutdown_requested=True
- The run() loop exits after the current pass completes
"""

from __future__ import annotations

import logging
import time
from typing import TYPE_CHECKING

import docker  # type: ignore[import-untyped]
import docker.errors  # type: ignore[import-untyped]

if TYPE_CHECKING:
    from docker import DockerClient

from sidecar_operator.config import OperatorConfig
from sidecar_operator.consumer_api import SidecarOperatorConsumer
from sidecar_operator.docker_api import (
    DockerUnavailableError,
    create_sidecar,
    list_managed_sidecars,
    read_container_ns_inodes,
    remove_sidecar,
)
from sidecar_operator.event_loop import EventLoopMixin
from sidecar_operator.models import ActualSidecarRef, SidecarStopContext
from sidecar_operator.reconcile import (
    CreateSidecar,
    ReconcilePlan,
    ReplaceSidecar,
    build_reconcile_plan,
)

logger = logging.getLogger(__name__)


class SidecarOperator(EventLoopMixin):
    """Orchestrates sidecar lifecycle for one or more consumers.

    Discovers target containers and managed sidecars, calls consumer hooks
    in the correct order, and executes reconcile plan actions.

    Attributes:
        config: operator configuration (scope, docker_host, interval).
        consumers: registered consumers, processed in registration order.
        shutdown_requested: set to True when a stop signal is received.
        reconcile_requested: set to True when a Docker event suggests an early
            reconcile pass is warranted (e.g. a container died).
        _last_poll_time: wall-clock timestamp of the last event poll, used to
            bound the since/until window for each Docker events query.
    """

    def __init__(
        self, config: OperatorConfig, client: "DockerClient | None" = None
    ) -> None:
        self.config = config
        self.client: "DockerClient" = client or docker.DockerClient(
            base_url=config.docker_host
        )
        self.consumers: list[SidecarOperatorConsumer] = []
        self.shutdown_requested: bool = False
        self.reconcile_requested: bool = False
        self._last_poll_time: float = time.time()

    def add_consumer(self, consumer: SidecarOperatorConsumer) -> None:
        """Register a consumer. Consumers are processed in registration order."""
        self.consumers.append(consumer)

    def request_shutdown(self, signal_name: str) -> None:
        """Set the shutdown flag. Safe to call from a signal handler."""
        logger.info("shutdown requested via %s", signal_name)
        self.shutdown_requested = True

    def run_once(self) -> None:
        """Run one full reconciliation pass across all consumers and targets."""
        scope = self.config.operator_scope

        # Discover managed sidecars (server-side filter + Python-side defensive check).
        actual_sidecars: list[ActualSidecarRef] = list_managed_sidecars(
            self.client, scope
        )
        sidecar_ids: set[str] = {ref.sidecar_container_id for ref in actual_sidecars}

        # Discover target containers: all scoped containers that are not managed sidecars.
        all_scoped = self.client.containers.list(
            all=True, filters={"label": f"garuda.operator-scope={scope}"}
        )
        targets = [c for c in all_scoped if c.id not in sidecar_ids]

        # Index actual sidecars by (consumer_name, target_name) for quick lookup.
        actual_by_key: dict[tuple[str, str], ActualSidecarRef] = {
            (ref.consumer_name, ref.target_name): ref for ref in actual_sidecars
        }

        # Track which (consumer_name, target_name) pairs are still desired.
        desired_keys: set[tuple[str, str]] = set()
        # Track pairs where the target exists but consumer rejected it — these get
        # "target_no_longer_matches" rather than "orphaned" as the stop reason.
        no_longer_matches_keys: set[tuple[str, str]] = set()

        for consumer in self.consumers:
            for target in targets:
                target_name_raw: str = target.name.lstrip("/")
                if not consumer.matches_target(target):
                    no_longer_matches_keys.add((consumer.name, target_name_raw))
                    continue

                target_name: str = target_name_raw
                key = (consumer.name, target_name)
                desired_keys.add(key)

                # Look up the existing sidecar container object (or None).
                existing_ref = actual_by_key.get(key)
                current_sidecar_container = None
                if existing_ref is not None:
                    try:
                        current_sidecar_container = self.client.containers.get(
                            existing_ref.sidecar_container_id
                        )
                    except docker.errors.NotFound:
                        logger.warning(
                            "could not fetch sidecar container %s for consumer=%s target=%s",
                            existing_ref.sidecar_name,
                            consumer.name,
                            target_name,
                        )

                # Handle dead targets: fire before_sidecar_stopped and remove sidecar.
                target_status: str = (
                    target.attrs.get("State", {}).get("Status", "")
                    or target.status
                    or ""
                )
                if target_status != "running":
                    logger.info(
                        "target %s is not running (status=%r); removing sidecar for consumer=%s",
                        target_name,
                        target_status,
                        consumer.name,
                    )
                    if existing_ref is not None:
                        self._stop_and_remove(
                            consumer=consumer,
                            actual=existing_ref,
                            sidecar_container=current_sidecar_container,
                            reason="target_died",
                        )
                    continue

                # on_reconcile — before any lifecycle action.
                try:
                    consumer.on_reconcile(
                        target, current_sidecar_container, self.client
                    )
                except (
                    Exception
                ):  # noqa: BLE001 — consumer callbacks must not crash the reconcile loop
                    logger.exception(
                        "on_reconcile failed for consumer=%s target=%s; skipping pair",
                        consumer.name,
                        target_name,
                    )
                    continue

                # Build desired spec; None means consumer wants no sidecar for this target.
                desired_spec = consumer.build_desired_sidecar(target)
                if desired_spec is None:
                    if existing_ref is not None:
                        self._stop_and_remove(
                            consumer=consumer,
                            actual=existing_ref,
                            sidecar_container=current_sidecar_container,
                            reason="target_no_longer_matches",
                        )
                    continue

                actual_list = [existing_ref] if existing_ref is not None else []

                # Enrich actual ref with namespace inode facts so the reconcile
                # planner can detect stale-namespace drift (target restarted and
                # received a new inode while sidecar remained in the old one).
                if existing_ref is not None:
                    self._enrich_actual_ref_ns_inodes(
                        actual=existing_ref,
                        target=target,
                        consumer=consumer,
                    )

                plan: ReconcilePlan = build_reconcile_plan(
                    desired=[desired_spec], actual=actual_list
                )

                for action in plan.actions:
                    if isinstance(action, CreateSidecar):
                        new_sidecar = create_sidecar(self.client, action.desired)
                        try:
                            consumer.on_sidecar_started(
                                target, new_sidecar, self.client
                            )
                        except (
                            Exception
                        ):  # noqa: BLE001 — consumer callbacks must not crash the reconcile loop
                            logger.exception(
                                "on_sidecar_started failed for consumer=%s target=%s",
                                consumer.name,
                                target_name,
                            )

                    elif isinstance(action, ReplaceSidecar):
                        self._stop_and_remove(
                            consumer=consumer,
                            actual=action.actual,
                            sidecar_container=current_sidecar_container,
                            reason="replace",
                        )
                        new_sidecar = create_sidecar(self.client, action.desired)
                        try:
                            consumer.on_sidecar_started(
                                target, new_sidecar, self.client
                            )
                        except (
                            Exception
                        ):  # noqa: BLE001 — consumer callbacks must not crash the reconcile loop
                            logger.exception(
                                "on_sidecar_started failed for consumer=%s target=%s",
                                consumer.name,
                                target_name,
                            )

        # Remove sidecars that are no longer desired.
        # "orphaned"              — no target container with that name exists at all.
        # "target_no_longer_matches" — target exists but consumer rejected it this pass.
        for ref in actual_sidecars:
            key = (ref.consumer_name, ref.target_name)
            if key not in desired_keys:
                if key in no_longer_matches_keys:
                    stop_reason = "target_no_longer_matches"
                else:
                    stop_reason = "orphaned"
                owning_consumer = next(
                    (c for c in self.consumers if c.name == ref.consumer_name), None
                )
                # Fetch the container so before_sidecar_stopped receives it.
                orphan_container = None
                try:
                    orphan_container = self.client.containers.get(
                        ref.sidecar_container_id
                    )
                except docker.errors.NotFound:
                    logger.warning(
                        "sidecar container %s (id=%s) not found during %s removal",
                        ref.sidecar_name,
                        ref.sidecar_container_id,
                        stop_reason,
                    )
                self._stop_and_remove(
                    consumer=owning_consumer,
                    actual=ref,
                    sidecar_container=orphan_container,
                    reason=stop_reason,
                )

    def run(self) -> None:
        """Run the continuous reconciliation loop until shutdown is requested."""
        self._install_signal_handlers()
        try:
            while not self.shutdown_requested:
                self.run_once()
                self._poll_events_once()
                self._sleep_until_next_interval()
        finally:
            self._close_event_stream()
            self.client.close()

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _stop_and_remove(
        self,
        consumer: SidecarOperatorConsumer | None,
        actual: ActualSidecarRef,
        sidecar_container,
        reason: str,
    ) -> None:
        """Fire before_sidecar_stopped (advisory) then remove the sidecar."""
        if consumer is not None and sidecar_container is not None:
            context = SidecarStopContext(
                reason=reason,  # type: ignore[arg-type]
                target_container_id=actual.target_container_id,
                target_name=actual.target_name,
                operator_scope=self.config.operator_scope,
                consumer_name=actual.consumer_name,
            )
            try:
                consumer.before_sidecar_stopped(context, sidecar_container, self.client)
            except (
                Exception
            ):  # noqa: BLE001 — consumer callbacks must not crash the reconcile loop
                logger.exception(
                    "before_sidecar_stopped failed for consumer=%s target=%s; removing anyway",
                    actual.consumer_name,
                    actual.target_name,
                )
        remove_sidecar(self.client, actual)

    def _enrich_actual_ref_ns_inodes(
        self,
        actual: ActualSidecarRef,
        target,
        consumer: SidecarOperatorConsumer,
    ) -> None:
        """Populate namespace inode fields on an ActualSidecarRef for drift detection.

        Reads effective Linux namespace inodes for the target and sidecar
        containers from ``/proc/<pid>/ns/{net,pid,ipc}`` and writes them into
        the ActualSidecarRef inode fields.  Only namespace types declared as
        shared by the consumer's ``shared_namespaces()`` are read; unused
        types retain empty strings so the reconciler skips their inode checks.

        Transient failures (container not found, PID=0, procfs race) leave
        the corresponding fields as empty strings.  The reconciler treats
        empty strings as "unknown — skip this check", preventing replace loops.

        DockerUnavailableError (API or communication failure) is caught and
        logged as a warning; enrichment is skipped for this pair, leaving all
        inode fields as empty strings so no spurious replacement is triggered.

        PermissionError reading ``/proc/<pid>/ns/*`` is caught and logged as an
        error; enrichment is skipped for this pair rather than aborting the
        whole reconcile pass.

        Args:
            actual: the ActualSidecarRef to enrich in-place.
            target: Docker SDK Container object for the target.
            consumer: the consumer that owns this sidecar pair; used to
                determine which namespaces are declared shared.
        """
        ns = consumer.shared_namespaces(target)
        target_id = target.id
        sidecar_id = actual.sidecar_container_id

        try:
            target_inodes = read_container_ns_inodes(self.client, target_id)
            sidecar_inodes = read_container_ns_inodes(self.client, sidecar_id)
        except DockerUnavailableError as exc:
            logger.warning(
                "ns inode enrichment skipped for consumer=%s target=%s: Docker unavailable: %s",
                consumer.name,
                actual.target_name,
                exc,
            )
            return
        except PermissionError as exc:
            logger.error(
                "ns inode enrichment skipped for consumer=%s target=%s: %s",
                consumer.name,
                actual.target_name,
                exc,
            )
            return

        if ns.network:
            actual.target_netns_inode = target_inodes.net
            actual.sidecar_netns_inode = sidecar_inodes.net
        if ns.pid:
            actual.target_pid_ns_inode = target_inodes.pid
            actual.sidecar_pid_ns_inode = sidecar_inodes.pid
        if ns.ipc:
            actual.target_ipc_ns_inode = target_inodes.ipc
            actual.sidecar_ipc_ns_inode = sidecar_inodes.ipc

    # _install_signal_handlers, _sleep_until_next_interval, _poll_events_once,
    # and _close_event_stream are inherited from EventLoopMixin (event_loop.py).
