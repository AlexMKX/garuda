"""CLI entrypoint for the FRR injector operator.

Parses config from a YAML file (path from env var or CLI arg),
detects self container ID, creates a SidecarOperator with FRRConsumer
registered, and runs the reconciliation loop.

Usage:
    python -m frr_injector.main [--config /path/to/config.yml]

Environment:
    FRR_INJECTOR_CONFIG: path to config YAML (default: /etc/frr-injector/config.yml)
    HOSTNAME: used as fallback for self container ID detection
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

import yaml

from frr_injector.config import BACKBONE_NETWORK, InjectorConfig
from frr_injector.consumer import FRRConsumer
from sidecar_operator.health import HealthServer
from network_manager.runtime import NetworkManager
from sidecar_operator.config import OperatorConfig
from sidecar_operator.runtime import SidecarOperator

logger = logging.getLogger("frr_injector")

DEFAULT_CONFIG_PATH = "/etc/frr-injector/config.yml"
DEFAULT_INTERVAL = 10.0
DEFAULT_HEALTH_PORT = 8080


def _detect_self_container_id() -> str:
    """Detect the container ID of the operator itself.

    Tries /proc/self/cgroup first (works in cgroup v1 and v2),
    then falls back to HOSTNAME env var.

    Returns:
        Container ID string, or empty string if detection fails.
    """
    # Try /proc/self/cgroup (cgroup v1)
    cgroup_path = Path("/proc/self/cgroup")
    if cgroup_path.exists():
        try:
            for line in cgroup_path.read_text().splitlines():
                # Format: hierarchy-ID:controller-list:cgroup-path
                # In Docker, the cgroup path often ends with the container ID
                parts = line.strip().split("/")
                if parts and len(parts[-1]) >= 12:
                    candidate = parts[-1]
                    # Docker container IDs are 64 hex chars
                    if len(candidate) == 64 and all(
                        c in "0123456789abcdef" for c in candidate
                    ):
                        return candidate
        except OSError:
            pass

    # Try /proc/self/mountinfo for cgroup v2
    mountinfo_path = Path("/proc/self/mountinfo")
    if mountinfo_path.exists():
        try:
            for line in mountinfo_path.read_text().splitlines():
                if "docker" in line or "containers" in line:
                    for part in line.split("/"):
                        if len(part) == 64 and all(
                            c in "0123456789abcdef" for c in part
                        ):
                            return part
        except OSError:
            pass

    # Fallback: HOSTNAME env
    hostname = os.environ.get("HOSTNAME", "")
    if hostname:
        logger.info("using HOSTNAME=%s as self container ID", hostname)
        return hostname

    logger.warning("could not detect self container ID")
    return ""


def _load_config(config_path: str) -> InjectorConfig:
    """Load operator config from a YAML file.

    Args:
        config_path: path to the YAML config file.

    Returns:
        Parsed InjectorConfig.

    Raises:
        SystemExit: if the file cannot be read or parsed.
    """
    path = Path(config_path)
    if not path.exists():
        logger.error("config file not found: %s", config_path)
        sys.exit(1)

    try:
        raw = yaml.safe_load(path.read_text())
    except Exception as exc:  # noqa: BLE001 — YAML/IO error at startup; safe to exit
        logger.error("failed to parse config %s: %s", config_path, exc)
        sys.exit(1)

    if raw is None:
        raw = {}

    # Inject self container ID if not already set
    if "self_container_id" not in raw or not raw["self_container_id"]:
        raw["self_container_id"] = _detect_self_container_id()

    try:
        return InjectorConfig(**raw)
    except (
        Exception
    ) as exc:  # noqa: BLE001 — pydantic validation at startup; safe to exit
        logger.error("invalid config: %s", exc)
        sys.exit(1)


def main(args_list: list[str] | None = None) -> None:
    """CLI entrypoint."""
    parser = argparse.ArgumentParser(
        description="OSPF injector operator — manages FRR sidecars for backbone-attached containers"
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("FRR_INJECTOR_CONFIG", DEFAULT_CONFIG_PATH),
        help="path to config YAML file",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help="reconcile loop interval in seconds",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="logging level",
    )
    args = parser.parse_args(args_list)

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    config = _load_config(args.config)

    logger.info(
        "starting ospf-injector: backbone=%s, interval=%.1fs",
        BACKBONE_NETWORK,
        args.interval,
    )

    # The health endpoint comes up before any other bootstrap work so that
    # container orchestration can observe the operator as "alive but not
    # ready". It only flips to ready once NetworkManager.ensure_all succeeds,
    # which is the contract that docker compose `--wait` relies on.
    health = HealthServer(port=DEFAULT_HEALTH_PORT)
    health.start()

    try:
        try:
            # Deferred import: config load/validation must work even without the docker SDK,
            # so tests and dry-runs can exercise main() without the runtime dependency.
            import docker

            client = docker.from_env()
        except (
            Exception
        ) as exc:  # noqa: BLE001 — docker SDK or ImportError at startup; safe to exit
            logger.error("failed to connect to Docker: %s", exc)
            sys.exit(1)

        try:
            NetworkManager(client=client).ensure_all(config.networks)
        except (
            Exception
        ) as exc:  # noqa: BLE001 — network bootstrap at startup; safe to exit
            logger.error("failed to ensure managed networks: %s", exc)
            sys.exit(1)

        # All bootstrap gates passed — downstream compose stacks can now
        # safely attach to the shared managed networks.
        health.mark_ready()

        operator_config = OperatorConfig(
            operator_scope=config.operator_scope,
            docker_host="unix:///var/run/docker.sock",
            reconcile_interval=args.interval,
        )
        operator = SidecarOperator(config=operator_config, client=client)
        operator.add_consumer(FRRConsumer(config=config))

        try:
            operator.run()
        except KeyboardInterrupt:
            logger.info("shutting down")
            sys.exit(0)
        except (
            Exception
        ) as exc:  # noqa: BLE001 — top-level operator crash; safe to exit
            logger.error("operator failed: %s", exc)
            sys.exit(1)
    finally:
        health.stop()


if __name__ == "__main__":
    main()
