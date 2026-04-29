"""Domain exceptions for the sidecar_operator package."""

from __future__ import annotations


class DockerUnavailableError(Exception):
    """Raised when the Docker API is unreachable or returns a communication error.

    Signals that the Docker daemon cannot be reached and the operator should
    fail fast, relying on its container restart policy for recovery.  This
    error is distinct from container-not-found or transient PID races, which
    are handled locally and never surfaced to callers.
    """
