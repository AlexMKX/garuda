"""OspfConfig model with from_labels classmethod and render_block method.

Owns all OSPF label parsing and validation via Pydantic v2 validators.
Owns OSPF config block rendering for both compact and raw modes.

Classes:
- OspfConfig: OSPF configuration parsed from garuda.frr.ospf.* labels.
- OspfDisabledError: raised when garuda.frr.ospf.enabled is explicitly not "true".
"""

from __future__ import annotations

import ipaddress
from typing import Self

from pydantic import BaseModel, Field, model_validator

from frr_injector._utils import parse_interfaces


# Label key constants
_LABEL_ENABLED = "garuda.frr.ospf.enabled"
_LABEL_ROUTER_ID = "garuda.frr.ospf.router_id"
_LABEL_INTERFACES = "garuda.frr.ospf.interfaces"
_LABEL_ACTIVE = "garuda.frr.ospf.active_interfaces"
_LABEL_DEFAULT = "garuda.frr.ospf.default_originate"
_LABEL_REDISTRIBUTE = "garuda.frr.ospf.redistribute"
_LABEL_EXTRA_B64 = "garuda.frr.extra_b64"

_REDISTRIBUTE_ALLOWLIST = frozenset({"connected", "kernel", "static"})

OSPF_AREA = "0.0.0.0"


class OspfDisabledError(Exception):
    """Raised when garuda.frr.ospf.enabled is explicitly disabled."""


class OspfConfig(BaseModel):
    """OSPF configuration parsed from garuda.frr.ospf.* labels."""

    router_id: ipaddress.IPv4Address | None = None
    default_originate: bool = False

    # Extended fields (compact mode only, forbidden when extra_b64 present)
    interfaces: list[str] = Field(default_factory=list)
    active_interfaces: list[str] = Field(default_factory=list)
    redistribute: list[str] = Field(default_factory=list)

    has_extra_b64: bool = False  # internal flag, not from labels
    transit_provider: bool = False

    @model_validator(mode="after")
    def _validate_mode_constraints(self) -> Self:
        """Validate mutual exclusion and subset constraints."""
        if self.has_extra_b64:
            if self.interfaces:
                raise ValueError(
                    "interfaces must be empty when garuda.frr.extra_b64 is present"
                )
            if self.active_interfaces:
                raise ValueError(
                    "active_interfaces must be empty when garuda.frr.extra_b64 is present"
                )
            if self.redistribute:
                raise ValueError(
                    "redistribute must be empty when garuda.frr.extra_b64 is present"
                )
        else:
            # Compact mode: active_interfaces must be subset of interfaces + backbone
            allowed = set(self.interfaces) | {"backbone"}
            if any(iface not in allowed for iface in self.active_interfaces):
                raise ValueError(
                    f"active_interfaces must be subset of interfaces + backbone; "
                    f"got {self.active_interfaces}, allowed {sorted(allowed)}"
                )
            # Compact mode: redistribute allowlist
            for r in self.redistribute:
                if r not in _REDISTRIBUTE_ALLOWLIST:
                    raise ValueError(
                        f"invalid redistribute value {r!r}; "
                        f"allowed: {sorted(_REDISTRIBUTE_ALLOWLIST)}"
                    )
        return self

    @property
    def ordered_interfaces(self) -> list[str]:
        """Interfaces with 'backbone' guaranteed first.

        Only meaningful in compact mode; returns [] when has_extra_b64 is True.
        """
        if self.has_extra_b64:
            return []
        others = [i for i in self.interfaces if i != "backbone"]
        return ["backbone"] + others

    @property
    def active_set(self) -> set[str]:
        """Effective active-interface set; backbone is always active in compact mode."""
        if self.has_extra_b64:
            return set()
        return {"backbone"} | set(self.active_interfaces)

    @classmethod
    def from_labels(cls, labels: dict[str, str]) -> OspfConfig | None:
        """Parse garuda.frr.ospf.* labels.

        Returns None if garuda.frr.ospf.enabled is absent.
        Raises OspfDisabledError if explicitly disabled.
        Raises ValueError or ValidationError on invalid labels.
        """
        enabled = labels.get(_LABEL_ENABLED)
        if enabled is None:
            return None
        if enabled != "true":
            raise OspfDisabledError(
                f"{_LABEL_ENABLED}={enabled!r} (must be 'true' to enable)"
            )

        has_extra_b64 = _LABEL_EXTRA_B64 in labels

        # Parse router_id (required in compact mode)
        raw_router_id = labels.get(_LABEL_ROUTER_ID)
        if raw_router_id is None and not has_extra_b64:
            raise ValueError(f"{_LABEL_ROUTER_ID} is required in compact mode")
        router_id = ipaddress.IPv4Address(raw_router_id) if raw_router_id else None

        raw_default = labels.get(_LABEL_DEFAULT, "false")
        if raw_default not in ("true", "false"):
            raise ValueError(f"invalid {_LABEL_DEFAULT}: {raw_default!r}")
        default_originate = raw_default == "true"

        # Compact-only fields
        interfaces: list[str] = []
        active_interfaces: list[str] = []
        redistribute: list[str] = []

        if has_extra_b64:
            # Compact-mode labels are forbidden when extra_b64 is present
            compact_labels = {_LABEL_INTERFACES, _LABEL_ACTIVE, _LABEL_REDISTRIBUTE}
            present_compact = compact_labels & set(labels.keys())
            if present_compact:
                raise ValueError(
                    f"compact-mode labels {sorted(present_compact)!r} are forbidden "
                    f"when {_LABEL_EXTRA_B64!r} is present"
                )
        else:
            raw_ifaces = labels.get(_LABEL_INTERFACES, "")
            interfaces = parse_interfaces(raw_ifaces)
            if not interfaces:
                raise ValueError(
                    f"{_LABEL_INTERFACES} must be non-empty in compact mode"
                )

            raw_active = labels.get(_LABEL_ACTIVE, "")
            active_interfaces = parse_interfaces(raw_active)

            raw_redistribute = labels.get(_LABEL_REDISTRIBUTE)
            if raw_redistribute is not None and raw_redistribute != "":
                redistribute = parse_interfaces(raw_redistribute)

        return cls(
            router_id=router_id,
            default_originate=default_originate,
            interfaces=interfaces,
            active_interfaces=active_interfaces,
            redistribute=redistribute,
            has_extra_b64=has_extra_b64,
        )

    def render_block(self) -> str:
        """Render the OSPF config block via Jinja template.

        The Jinja environment is owned by render.py; imported lazily here
        to avoid a circular import (render.py TYPE_CHECKING-imports
        OspfConfig).
        """
        from frr_injector.render import _jinja_env

        return _jinja_env.get_template("ospf_block.conf.j2").render(cfg=self)
