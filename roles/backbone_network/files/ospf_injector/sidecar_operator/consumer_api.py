"""Consumer ABC for the generic sidecar operator.

Defines the SidecarOperatorConsumer abstract base class that all operator
consumers must inherit. Consumers declare what sidecars they want (via
build_desired_sidecar) and receive lifecycle hooks for reconcile events.

All hook boundaries use Docker SDK objects directly — no wrapper classes.

Classes:
- SidecarOperatorConsumer: abstract base class for consumer implementations.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from docker import DockerClient
    from docker.models.containers import Container

from sidecar_operator.models import (
    DesiredSidecarSpec,
    SharedNamespaces,
    SidecarStopContext,
)


class SidecarOperatorConsumer(ABC):
    """Abstract base class for sidecar operator consumers.

    Consumers inherit this ABC to participate in the sidecar lifecycle.
    The operator calls these methods during reconciliation and lifecycle events.

    All methods that receive Docker objects operate on docker.models.containers.Container
    instances directly — no wrapper types are used at runtime/hook boundaries.

    Attributes:
        name: unique consumer identifier used as the consumer_name in sidecar labels
            and as the join-key component in reconcile planning (e.g. "ospf", "pbr").
        sidecar_revision: opaque revision string stamped onto managed sidecars as
            the garuda.sidecar-revision label. Changing this triggers replacement.
    """

    name: str
    sidecar_revision: str

    @abstractmethod
    def matches_target(self, container: "Container") -> bool:
        """Return True if this consumer wants to manage a sidecar for the container.

        Called for every discovered container during target enumeration. Containers
        for which this returns False are invisible to this consumer.

        Args:
            container: a Docker SDK Container object for the candidate target.

        Returns:
            True if a sidecar should be managed for this target; False otherwise.
        """

    @abstractmethod
    def shared_namespaces(self, target: "Container") -> SharedNamespaces:
        """Declare which Linux namespaces the sidecar should share with the target.

        Called when building the desired sidecar spec. The returned value is
        used both for creating the container and for drift detection.

        Args:
            target: the Docker SDK Container object for the target.

        Returns:
            A SharedNamespaces instance declaring network/pid/ipc sharing.
        """

    @abstractmethod
    def build_desired_sidecar(self, target: "Container") -> DesiredSidecarSpec | None:
        """Build the full desired sidecar specification for a target container.

        Called during reconciliation to determine the desired sidecar state.
        Return None to suppress sidecar creation (e.g. when configuration is
        incomplete or the consumer does not want a sidecar for this specific target).

        Args:
            target: the Docker SDK Container object for the target.

        Returns:
            A DesiredSidecarSpec, or None to skip sidecar creation for this target.
        """

    @abstractmethod
    def on_reconcile(
        self,
        target: "Container",
        sidecar: "Container | None",
        docker: "DockerClient",
    ) -> None:
        """Called after each reconciliation pass for a managed target.

        Fired regardless of whether any action was taken. Consumers can use this
        to synchronise in-sidecar configuration (e.g. reload FRR config).

        Args:
            target: the Docker SDK Container object for the target.
            sidecar: the sidecar Container if it exists and is running; None otherwise.
            docker: Docker client for any additional API calls.
        """

    @abstractmethod
    def on_sidecar_started(
        self,
        target: "Container",
        sidecar: "Container",
        docker: "DockerClient",
    ) -> None:
        """Called immediately after a new sidecar container is started.

        Fired after CreateSidecar or ReplaceSidecar actions when the new sidecar
        container has been created and started successfully.

        Args:
            target: the Docker SDK Container object for the target.
            sidecar: the newly started sidecar Container.
            docker: Docker client for any additional API calls.
        """

    @abstractmethod
    def before_sidecar_stopped(
        self,
        context: SidecarStopContext,
        sidecar: "Container",
        docker: "DockerClient",
    ) -> None:
        """Called before a managed sidecar is removed.

        Fired before every sidecar removal, regardless of reason. This hook is
        advisory — the sidecar is always removed unconditionally after it returns,
        even if this method raises an exception.

        Hook failures are target-scoped: this (consumer_name, target_name) pair
        fails but other pairs continue reconciliation.

        Args:
            context: metadata about why the sidecar is being stopped.
            sidecar: the sidecar Container about to be removed.
            docker: Docker client for any additional API calls.
        """
