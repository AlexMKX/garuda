"""Desired vs actual comparison and action planning for the generic sidecar operator.

The reconcile planner accepts desired sidecars (from consumer declarations)
and actual managed sidecars (from Docker label discovery). It produces a
ReconcilePlan with typed actions:

- CreateSidecar: no actual sidecar exists for this (consumer_name, target_name) pair.
- ReplaceSidecar: actual sidecar exists but has drifted from desired spec.
- RemoveSidecar: actual sidecar exists but the consumer no longer declares it.

Drift detection covers:
- non-running sidecar state
- target_container_id mismatch (binding drift after target restart)
- any label in desired not matching the same key in actual labels
- namespace-sharing metadata mismatch (network_mode, pid_mode, ipc_mode vs SharedNamespaces)
- effective namespace inode identity mismatch for declared-shared namespaces
  (target inode != sidecar inode after target restart, skipped when either inode is empty)

The planner does NOT execute actions — that is the runtime's responsibility.
Join key: (consumer_name, target_name) — two consumers for the same target are
treated as independent sidecars.
"""

from __future__ import annotations

import logging

from pydantic import BaseModel, Field

from sidecar_operator.models import ActualSidecarRef, DesiredSidecarSpec

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Action types
# ---------------------------------------------------------------------------


class CreateSidecar(BaseModel):
    """Action: create a new managed sidecar for a (consumer_name, target_name) pair."""

    desired: DesiredSidecarSpec


class ReplaceSidecar(BaseModel):
    """Action: remove existing sidecar and create a new one (drift detected)."""

    desired: DesiredSidecarSpec
    actual: ActualSidecarRef


class RemoveSidecar(BaseModel):
    """Action: remove an orphaned managed sidecar (no longer desired)."""

    actual: ActualSidecarRef


# Union of all action types
Action = CreateSidecar | ReplaceSidecar | RemoveSidecar


# ---------------------------------------------------------------------------
# Reconcile plan
# ---------------------------------------------------------------------------


class ReconcilePlan(BaseModel):
    """The result of comparing desired vs actual sidecar state.

    Attributes:
        actions: ordered list of actions to execute. Each action is
            independently scoped to one (consumer_name, target_name) pair.
    """

    actions: list[Action] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Planner
# ---------------------------------------------------------------------------


def build_reconcile_plan(
    desired: list[DesiredSidecarSpec],
    actual: list[ActualSidecarRef],
) -> ReconcilePlan:
    """Compare desired and actual sidecar state and produce an action plan.

    Matching is by (consumer_name, target_name) pair:
    - desired with no matching actual -> CreateSidecar
    - desired with matching actual but drifted -> ReplaceSidecar
    - actual with no matching desired -> RemoveSidecar
    - desired matching actual with no drift -> no action

    Args:
        desired: desired sidecars declared by consumers.
        actual: actual managed sidecars from Docker label discovery.

    Returns:
        A ReconcilePlan with typed actions, one per drifted or missing pair.
    """
    actions: list[Action] = []

    # Index by (consumer_name, target_name) join key
    actual_by_key: dict[tuple[str, str], ActualSidecarRef] = {}
    for a in actual:
        key = (a.consumer_name, a.target_name)
        if key in actual_by_key:
            logger.warning(
                "duplicate actual sidecar for consumer=%s target=%s; keeping %s, ignoring %s",
                a.consumer_name,
                a.target_name,
                actual_by_key[key].sidecar_container_id,
                a.sidecar_container_id,
            )
        else:
            actual_by_key[key] = a
    desired_by_key: dict[tuple[str, str], DesiredSidecarSpec] = {}
    for d in desired:
        key = (d.consumer_name, d.target_name)
        if key in desired_by_key:
            logger.warning(
                "duplicate desired sidecar for consumer=%s target=%s; keeping first, ignoring %s",
                d.consumer_name,
                d.target_name,
                d.sidecar_name,
            )
        else:
            desired_by_key[key] = d

    for key, desired_spec in desired_by_key.items():
        actual_ref = actual_by_key.get(key)
        if actual_ref is None:
            actions.append(CreateSidecar(desired=desired_spec))
            logger.info(
                "plan: create sidecar consumer=%s target=%s",
                desired_spec.consumer_name,
                desired_spec.target_name,
            )
        elif _has_drift(desired_spec, actual_ref):
            actions.append(ReplaceSidecar(desired=desired_spec, actual=actual_ref))
            logger.info(
                "plan: replace sidecar consumer=%s target=%s (drift detected)",
                desired_spec.consumer_name,
                desired_spec.target_name,
            )
        else:
            logger.debug(
                "plan: sidecar consumer=%s target=%s is up to date",
                desired_spec.consumer_name,
                desired_spec.target_name,
            )

    for key, actual_ref in actual_by_key.items():
        if key not in desired_by_key:
            actions.append(RemoveSidecar(actual=actual_ref))
            logger.info(
                "plan: remove orphaned sidecar consumer=%s target=%s",
                actual_ref.consumer_name,
                actual_ref.target_name,
            )

    return ReconcilePlan(actions=actions)


def _has_drift(desired: DesiredSidecarSpec, actual: ActualSidecarRef) -> bool:
    """Check whether the actual sidecar has drifted from the desired spec.

    Drift is detected when any of the following conditions hold:
    - sidecar is not in 'running' state
    - target_container_id differs (target container was replaced)
    - any label key present in desired is absent or has a different value in actual;
      labels present in actual but absent in desired are not considered drift
    - namespace-sharing config (network/pid/ipc) does not match declared SharedNamespaces

    Args:
        desired: the desired sidecar specification from the consumer.
        actual: the actual sidecar state from Docker discovery.

    Returns:
        True if replacement is needed; False if the sidecar is up to date.
    """
    if actual.state != "running":
        logger.info(
            "drift: sidecar %s is in state %r (not running)",
            actual.sidecar_name,
            actual.state,
        )
        return True

    if desired.target_container_id != actual.target_container_id:
        logger.info(
            "drift: sidecar %s target_container_id changed (%r -> %r)",
            actual.sidecar_name,
            actual.target_container_id,
            desired.target_container_id,
        )
        return True

    for label_key, desired_value in desired.labels.items():
        if actual.labels.get(label_key) != desired_value:
            logger.info(
                "drift: sidecar %s label %r mismatch (desired=%r actual=%r)",
                actual.sidecar_name,
                label_key,
                desired_value,
                actual.labels.get(label_key),
            )
            return True

    if _has_namespace_drift(desired, actual):
        return True

    return False


def _has_namespace_drift(desired: DesiredSidecarSpec, actual: ActualSidecarRef) -> bool:
    """Check whether namespace-sharing modes have drifted from declared SharedNamespaces.

    Two drift conditions are checked for each declared-shared namespace:

    1. Metadata mode mismatch — Docker HostConfig field does not equal
       ``container:<target_container_id>`` for a shared namespace, or does equal
       it for an unshared namespace.

    2. Effective inode identity mismatch — both metadata mode and target_container_id
       appear correct, but the sidecar is still bound to the old Linux namespace inode
       (e.g. after the target container restarted and received a new namespace inode).
       This check is skipped when either inode string is empty, because empty strings
       indicate a transient unresolvable state (e.g. container still initialising);
       forcing replacement on unknown state would cause replace loops.

    Args:
        desired: the desired sidecar specification.
        actual: the actual sidecar state.

    Returns:
        True if any namespace mode or effective inode has drifted; False otherwise.
    """
    ns = desired.shared_namespaces
    target_id = desired.target_container_id
    expected_container_mode = f"container:{target_id}"

    # (shared_flag, actual_mode, target_inode, sidecar_inode, field_label)
    checks = [
        (
            ns.network,
            actual.network_mode,
            actual.target_netns_inode,
            actual.sidecar_netns_inode,
            "network_mode",
        ),
        (
            ns.pid,
            actual.pid_mode,
            actual.target_pid_ns_inode,
            actual.sidecar_pid_ns_inode,
            "pid_mode",
        ),
        (
            ns.ipc,
            actual.ipc_mode,
            actual.target_ipc_ns_inode,
            actual.sidecar_ipc_ns_inode,
            "ipc_mode",
        ),
    ]

    for shared, actual_mode, target_inode, sidecar_inode, field_name in checks:
        if shared:
            if actual_mode != expected_container_mode:
                logger.info(
                    "drift: sidecar %s %s should be %r but is %r",
                    actual.sidecar_name,
                    field_name,
                    expected_container_mode,
                    actual_mode,
                )
                return True
            # Effective inode check: only when both inodes are known (non-empty).
            if target_inode and sidecar_inode and target_inode != sidecar_inode:
                logger.info(
                    "drift: sidecar %s %s inode mismatch (target=%r sidecar=%r)",
                    actual.sidecar_name,
                    field_name,
                    target_inode,
                    sidecar_inode,
                )
                return True
        else:
            if actual_mode == expected_container_mode:
                logger.info(
                    "drift: sidecar %s %s should not share namespace but is %r",
                    actual.sidecar_name,
                    field_name,
                    actual_mode,
                )
                return True

    return False
