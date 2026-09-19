"""Load and validate ``rules/*.yaml`` (VA-001).

``load_rules(directory)`` parses every ``<id>.yaml`` directly under the directory (fixtures
live in ``rules/fixtures/`` and are not rules), validates each with ``RuleConfig`` and checks
that the file name matches the ``id``. Any problem raises ``RuleConfigError`` listing every
bad file, so a broken rule fails the API / worker / job at startup and the test suite in CI.

``get_rule_set()`` is the process-wide cached set from ``settings.rules_dir`` (default: the
monorepo ``rules/``). ``check_registry`` proves every YAML has an implementation and every
implementation a YAML.
"""

from __future__ import annotations

from collections.abc import Iterable, Iterator, Mapping
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from pydantic import ValidationError

from farmerapp.logging import get_logger
from farmerapp.rules.schema import Mode, RuleConfig
from farmerapp.settings import get_settings

log = get_logger("farmerapp.rules")

_PARENTS = Path(__file__).resolve().parents
#: apps/api/farmerapp/rules/loader.py -> the monorepo root's rules/.
DEFAULT_RULES_DIR = (_PARENTS[4] if len(_PARENTS) > 4 else _PARENTS[-1]) / "rules"


class RuleConfigError(ValueError):
    """One or more rule files are invalid."""


@dataclass(frozen=True)
class RuleSet:
    rules: Mapping[str, RuleConfig]
    directory: Path

    def __iter__(self) -> Iterator[RuleConfig]:
        return iter(self.rules[k] for k in sorted(self.rules))

    def get(self, rule_id: str) -> RuleConfig:
        return self.rules[rule_id]

    def for_mode(self, mode: Mode, *, trigger: str | None = None) -> list[RuleConfig]:
        out = [r for r in self if mode in r.mode]
        if trigger is not None:
            out = [r for r in out if trigger in r.triggers]
        return out


def _parse(path: Path) -> RuleConfig:
    raw: Any = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise RuleConfigError(f"{path.name}: not a YAML mapping")
    config = RuleConfig.model_validate(raw)
    if path.stem != config.id:
        raise RuleConfigError(f"{path.name}: file name must be {config.id}.yaml")
    return config


def load_rules(directory: Path | str) -> RuleSet:
    root = Path(directory)
    if not root.is_dir():
        raise RuleConfigError(f"rules directory {root} does not exist")
    rules: dict[str, RuleConfig] = {}
    problems: list[str] = []
    for path in sorted(root.glob("*.yaml")):
        try:
            config = _parse(path)
        except (ValidationError, yaml.YAMLError, RuleConfigError) as exc:
            problems.append(f"{path.name}: {exc}")
            continue
        rules[config.id] = config
    if problems:
        raise RuleConfigError("invalid rule files:\n" + "\n".join(problems))
    return RuleSet(rules=rules, directory=root)


def rules_dir() -> Path:
    configured = get_settings().rules_dir
    return Path(configured) if configured else DEFAULT_RULES_DIR


@lru_cache(maxsize=1)
def get_rule_set() -> RuleSet:
    """The validated rules of this process (cached; ``get_rule_set.cache_clear()`` reloads).

    Invalid files always raise. A *missing* directory (an image built without ``rules/``) is
    logged as an error and yields no rules, so the API still serves; ``RULES_DIR`` fixes it.
    """
    directory = rules_dir()
    if not directory.is_dir():
        log.error("rules_dir_missing", rules_dir=str(directory))
        return RuleSet(rules={}, directory=directory)
    return load_rules(directory)


def validate_rules() -> RuleSet:
    """Startup check (API, worker, jobs): the YAML parses and matches the implementations."""
    from farmerapp.rules.registry import implementations

    rule_set = get_rule_set()
    if rule_set.rules:
        problems = check_registry(rule_set, implementations())
        if problems:
            raise RuleConfigError(
                "rules do not match their implementations:\n" + "\n".join(problems)
            )
        log.info(
            "rules_loaded",
            rules_dir=str(rule_set.directory),
            count=len(rule_set.rules),
            rules=sorted(rule_set.rules),
        )
    return rule_set


def check_registry(rule_set: RuleSet, implemented: Mapping[str, object]) -> list[str]:
    """Mismatches between YAML files and ``@rule`` implementations (empty = consistent)."""
    missing_impl = [
        f"{rid}: YAML without an implementation" for rid in rule_set.rules if rid not in implemented
    ]
    missing_yaml = [
        f"{rid}: implementation without rules/{rid}.yaml"
        for rid in implemented
        if rid not in rule_set.rules
    ]
    return sorted(missing_impl + missing_yaml)


FIXTURE_CASES = ("positive", "negative")


def check_fixtures(rule_set: RuleSet, rule_ids: Iterable[str] = ()) -> list[str]:
    """VA-007: every rule has ``fixtures/<id>/positive.yaml`` and ``negative.yaml`` next to
    the rule files (empty = complete). ``rule_ids`` adds ids known only from the registry."""
    fixtures = rule_set.directory / "fixtures"
    return [
        f"{rid}: missing fixtures/{rid}/{case}.yaml"
        for rid in sorted(set(rule_set.rules) | set(rule_ids))
        for case in FIXTURE_CASES
        if not (fixtures / rid / f"{case}.yaml").is_file()
    ]


__all__ = [
    "DEFAULT_RULES_DIR",
    "FIXTURE_CASES",
    "RuleConfigError",
    "RuleSet",
    "check_fixtures",
    "check_registry",
    "get_rule_set",
    "load_rules",
    "rules_dir",
    "validate_rules",
]
