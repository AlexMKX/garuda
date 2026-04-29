"""TransitConfig model with from_labels classmethod.

Owns all transit routing label parsing and validation. Transit routing is a
system-level concern: the provider advertises a tagged OSPF default, and
consumers route VPN traffic through it via PBR.

Classes:
- TransitConfig: Transit routing configuration parsed from garuda.transit.* labels.
"""

from __future__ import annotations

from typing import Self

from pydantic import BaseModel, Field, model_validator

from frr_injector._utils import parse_interfaces

_LABEL_PROVIDER = "garuda.transit.provider"
_LABEL_INTERFACES = "garuda.transit.interfaces"


class TransitConfig(BaseModel):
    """Transit routing configuration parsed from garuda.transit.* labels."""

    provider: bool = False
    interfaces: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def _validate_mutual_exclusion(self) -> Self:
        """Provider and interfaces are mutually exclusive."""
        if self.provider and self.interfaces:
            raise ValueError(
                "garuda.transit.provider and garuda.transit.interfaces are "
                "mutually exclusive: a workload is either the transit provider "
                "or a transit consumer, not both"
            )
        return self

    @classmethod
    def from_labels(cls, labels: dict[str, str]) -> TransitConfig | None:
        """Parse garuda.transit.* labels.

        Returns None if no garuda.transit.* labels are present.
        Raises ValueError on invalid label values or mutual exclusion violation.
        """
        raw_provider = labels.get(_LABEL_PROVIDER)
        raw_interfaces = labels.get(_LABEL_INTERFACES)

        if raw_provider is None and raw_interfaces is None:
            return None

        provider = False
        if raw_provider is not None:
            if raw_provider != "true":
                raise ValueError(
                    f"garuda.transit.provider must be 'true', got {raw_provider!r}"
                )
            provider = True

        interfaces: list[str] = []
        if raw_interfaces is not None:
            interfaces = parse_interfaces(raw_interfaces)
            if not interfaces:
                raise ValueError(
                    "garuda.transit.interfaces must be non-empty when present"
                )

        return cls(provider=provider, interfaces=interfaces)
