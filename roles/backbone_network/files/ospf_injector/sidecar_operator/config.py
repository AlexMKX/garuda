"""Configuration model for the generic sidecar operator.

Classes:
- OperatorConfig: runtime configuration for a SidecarOperator instance.
"""

from __future__ import annotations

from pydantic import BaseModel


class OperatorConfig(BaseModel):
    """Runtime configuration for a SidecarOperator instance.

    Attributes:
        operator_scope: label value used to identify containers managed by
            this operator instance (garuda.operator-scope=<operator_scope>).
        docker_host: Docker daemon socket URL. Defaults to the standard
            Unix socket path.
        reconcile_interval: seconds to wait between reconciliation passes
            in the continuous run() loop.
    """

    operator_scope: str
    docker_host: str = "unix:///var/run/docker.sock"
    reconcile_interval: float = 30.0
