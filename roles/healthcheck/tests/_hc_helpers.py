"""Shared helpers for healthcheck role tests."""

from pathlib import Path
import yaml

ROLE_ROOT = Path(__file__).resolve().parents[1]


def load_yaml(path):
    full = Path(path) if Path(path).is_absolute() else ROLE_ROOT / path
    return yaml.safe_load(full.read_text(encoding="utf-8"))
