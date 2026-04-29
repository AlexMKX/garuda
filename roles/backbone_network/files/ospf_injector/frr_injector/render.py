"""FRR daemon, vtysh, and frr.conf rendering via Jinja2 templates."""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

import jinja2

from frr_injector.config import (
    TRANSIT_METRIC,
    TRANSIT_METRIC_TYPE,
    TRANSIT_ROUTE_MAP,
    TRANSIT_TAG,
)
from frr_injector.ospf_config import OSPF_AREA

if TYPE_CHECKING:
    from frr_injector.ospf_config import OspfConfig

_TEMPLATES_DIR = Path(__file__).parent / "templates"

_PREAMBLE = [
    "frr defaults traditional",
    "log syslog informational",
    # Confine zebra's kernel-nexthop tracking to its own protocols. Without
    # this, zebra reclaims any kernel nhid referenced by a route (regardless
    # of nhid proto) and rewrites it to its RIB resolution — overwriting
    # ipt_server's NHG members within ~1s of installation.
    "zebra nexthop proto only",
]

_jinja_env = jinja2.Environment(
    loader=jinja2.FileSystemLoader(str(_TEMPLATES_DIR)),
    keep_trailing_newline=False,
    trim_blocks=True,
    lstrip_blocks=True,
    undefined=jinja2.StrictUndefined,
)
_jinja_env.globals.update(
    OSPF_AREA=OSPF_AREA,
    TRANSIT_ROUTE_MAP=TRANSIT_ROUTE_MAP,
    TRANSIT_TAG=TRANSIT_TAG,
    TRANSIT_METRIC=TRANSIT_METRIC,
    TRANSIT_METRIC_TYPE=TRANSIT_METRIC_TYPE,
)


def render_frr_conf(
    hostname: str,
    ospf_config: "OspfConfig",
    extra_body: "str | None",
) -> str:
    """Render complete frr.conf from model state and Jinja templates."""
    return _jinja_env.get_template("frr.conf.j2").render(
        preamble=_PREAMBLE,
        hostname=hostname,
        extra_body=extra_body,
        ospf_block=ospf_config.render_block(),
    )


def render_daemons() -> str:
    """Render the FRR daemons enablement file.

    Returns:
        The rendered daemons file content.
    """
    return _jinja_env.get_template("daemons.j2").render(pbr_enabled=False)


def render_vtysh_conf() -> str:
    """Render the FRR vtysh.conf file.

    Returns:
        The vtysh.conf content (static, no templating needed).
    """
    return (_TEMPLATES_DIR / "vtysh.conf").read_text()
