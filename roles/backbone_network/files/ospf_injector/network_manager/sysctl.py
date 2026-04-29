"""Host-side sysctl application from within a ``network_mode: none`` container.

Why this exists
---------------
The operator runs with ``network_mode: none`` so it cannot use
``network_mode: host`` tricks. To flip bridge-level ``proxy_arp`` on the host
(where the managed backbone/border bridges live) it enters the host network
namespace via ``nsenter --net=/proc/1/ns/net`` and writes directly into
``/proc/sys/net/ipv4/conf/<bridge>/proxy_arp``.

Why not ``sysctl -w``
---------------------
``sysctl`` is shipped by the Debian ``procps`` package and is **not** present
in ``python:3.12-slim``. Installing procps purely to flip one kernel flag is
bloat and adds a release-time dependency we do not otherwise need. Writing
through procfs is the canonical Linux mechanism that ``sysctl(8)`` itself
uses under the hood, and requires only ``sh`` + ``echo`` which every Debian
base image already has.
"""

from __future__ import annotations

import re
import subprocess

# Linux interface names are 1..15 chars from [A-Za-z0-9_.-]. Enforcing this
# at the boundary removes any possibility of shell injection through the
# bridge name despite the inputs being trusted config today. The spec lives
# in ``man 7 netdevice`` and is echoed by iproute2.
_IFACE_NAME_RE = re.compile(r"^[A-Za-z0-9_.\-]{1,15}$")


def _validate_bridge_name(bridge_name: str) -> None:
    if not _IFACE_NAME_RE.match(bridge_name):
        raise ValueError(
            f"refusing to use unsafe bridge name {bridge_name!r}: "
            f"must match {_IFACE_NAME_RE.pattern}"
        )


class HostSysctlRunner:
    """Applies host-netns sysctl settings from within the container via nsenter.

    Uses ``nsenter --net=/proc/1/ns/net`` to reach the host network namespace
    from a privileged container running with ``pid: host``. This is the only
    supported mechanism for setting bridge-level sysctl on the host without
    requiring ``network_mode: host``, which would defeat the point of
    running the operator with ``network_mode: none``.

    The command writes directly into procfs (see module docstring for the
    rationale) rather than shelling out to the ``sysctl`` binary.
    """

    def ensure_proxy_arp(self, bridge_name: str, value: int) -> None:
        """Set ``net.ipv4.conf.<bridge_name>.proxy_arp`` on the host netns.

        Args:
            bridge_name: The name of the Linux bridge interface on the host.
                Must be a valid Linux interface name (see ``man 7 netdevice``).
            value: ``0`` to disable, ``1`` to enable proxy ARP.

        Raises:
            ValueError: If ``bridge_name`` contains characters that are not
                valid in a Linux interface name. This blocks shell-injection
                vectors through the interpolated procfs path.
            RuntimeError: If ``nsenter`` or the shell write exits non-zero.
        """
        _validate_bridge_name(bridge_name)
        proc_path = f"/proc/sys/net/ipv4/conf/{bridge_name}/proxy_arp"
        # ``sh -c 'echo N > /proc/sys/...'`` is the minimal shell form that
        # resolves the procfs path inside the *host* network namespace we
        # just entered. ``echo`` is a shell builtin and ``sh`` is in every
        # Debian-based image, so we pay no packaging cost.
        shell_cmd = f"echo {int(value)} > {proc_path}"
        try:
            subprocess.run(
                [
                    "nsenter",
                    "--net=/proc/1/ns/net",
                    "sh",
                    "-c",
                    shell_cmd,
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(
                f"nsenter failed to set proxy_arp={value} on {bridge_name}: "
                f"{exc.stderr.strip()}"
            ) from exc
