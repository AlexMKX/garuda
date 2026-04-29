"""Generic sidecar operator — lifecycle management for consumer-driven sidecars.

This package provides a reusable, consumer-agnostic sidecar lifecycle system.
Consumers (e.g. ospf, pbr) declare what sidecars they want via DesiredSidecarSpec;
the operator reconciles actual Docker state against those declarations.

Key modules:
- models: shared data models (DesiredSidecarSpec, ActualSidecarRef, SharedNamespaces)
- reconcile: build_reconcile_plan — produces typed action plans (create/replace/remove)
- config: OperatorConfig — runtime configuration (scope, docker_host, interval)
- runtime: SidecarOperator — reconciliation loop, signal handling, hook orchestration

The reconcile planner keys on (consumer_name, target_name) so that multiple
consumers targeting the same container are treated as independent sidecars.
"""

from sidecar_operator.config import OperatorConfig
from sidecar_operator.runtime import SidecarOperator

__all__ = ["OperatorConfig", "SidecarOperator"]
