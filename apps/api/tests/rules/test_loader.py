"""VA-001: rule files are validated YAML; a broken file fails the loader (and so CI and the
app start); tenant overrides and YAML-only tuning."""

from __future__ import annotations

import shutil
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest
import yaml
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.rules import loader
from farmerapp.rules.loader import (
    DEFAULT_RULES_DIR,
    RuleConfigError,
    check_registry,
    get_rule_set,
    load_rules,
    validate_rules,
)
from farmerapp.rules.registry import implementations, rule
from farmerapp.rules.schema import Mode, RuleConfig
from farmerapp.settings import get_settings
from tests.rules.harness import P0_RULES, assert_expected, load_fixture, run_fixture

VALID: dict[str, Any] = {
    "id": "VA-F99",
    "version": 1,
    "title": "Test rule",
    "subject": "farmer",
    "mode": "batch",
    "severity": "low",
    "owner_role": "store_manager",
    "sla_hours": 24,
    "params": {"limit": 3, "strict": True},
}


def _write(directory: Path, data: dict[str, Any], name: str | None = None) -> Path:
    path = directory / f"{name or data['id']}.yaml"
    path.write_text(yaml.safe_dump(data), encoding="utf-8")
    return path


@pytest.fixture
def rules_copy(tmp_path: Path) -> Path:
    target = tmp_path / "rules"
    target.mkdir()
    for path in DEFAULT_RULES_DIR.glob("*.yaml"):
        shutil.copy(path, target / path.name)
    return target


@pytest.fixture
def rules_dir_env(monkeypatch: pytest.MonkeyPatch) -> Iterator[Any]:
    def _point(path: Path) -> None:
        monkeypatch.setenv("RULES_DIR", str(path))
        get_settings.cache_clear()
        get_rule_set.cache_clear()

    yield _point
    monkeypatch.delenv("RULES_DIR", raising=False)
    get_settings.cache_clear()
    get_rule_set.cache_clear()


def test_repository_rules_are_valid_and_implemented() -> None:
    rule_set = load_rules(DEFAULT_RULES_DIR)
    assert check_registry(rule_set, implementations()) == []
    for config in rule_set:
        assert config.version >= 1
        assert config.sla_hours > 0
    f06 = rule_set.get("VA-F06")
    assert f06.mode == (Mode.EVENT, Mode.BATCH)
    assert f06.triggers == ("farmer.registered",)
    assert [r.id for r in rule_set.for_mode(Mode.EVENT, trigger="farmer.registered")] == ["VA-F06"]
    assert {r.id for r in rule_set.for_mode(Mode.INLINE)} == {"VA-F01", "VA-F02", "VA-F03"}


@pytest.mark.parametrize(
    ("change", "message"),
    [
        ({"unknown_key": 1}, "unknown_key"),
        ({"mode": "nightly"}, "mode"),
        ({"severity": "critical"}, "severity"),
        ({"id": "F02"}, "id"),
        ({"sla_hours": 0}, "sla_hours"),
        ({"mode": ["batch", "batch"]}, "twice"),
        ({"mode": "event"}, "trigger"),
        ({"triggers": ["farmer.registered"]}, "only meaningful"),
        ({"tenant_overrides": {"fcc": {"params": {"limt": 4}}}}, "unknown keys"),
        ({"tenant_overrides": {"fcc": {"params": {"limit": "four"}}}}, "type of the default"),
        ({"tenant_overrides": {"fcc": {"params": {"strict": 1}}}}, "type of the default"),
    ],
)
def test_invalid_rule_file_fails_the_loader(
    tmp_path: Path, change: dict[str, Any], message: str
) -> None:
    _write(tmp_path, {**VALID, **change}, name="VA-F99")
    with pytest.raises(RuleConfigError, match=message):
        load_rules(tmp_path)


def test_file_name_must_match_the_id(tmp_path: Path) -> None:
    _write(tmp_path, VALID, name="VA-F98")
    with pytest.raises(RuleConfigError, match=r"must be VA-F99\.yaml"):
        load_rules(tmp_path)


def test_not_a_mapping_and_broken_yaml(tmp_path: Path) -> None:
    (tmp_path / "VA-F97.yaml").write_text("- just\n- a list\n", encoding="utf-8")
    (tmp_path / "VA-F96.yaml").write_text("id: [unclosed\n", encoding="utf-8")
    with pytest.raises(RuleConfigError) as exc:
        load_rules(tmp_path)
    assert "VA-F97.yaml" in str(exc.value) and "VA-F96.yaml" in str(exc.value)


def test_missing_directory(tmp_path: Path) -> None:
    with pytest.raises(RuleConfigError, match="does not exist"):
        load_rules(tmp_path / "nope")


def test_tenant_overrides() -> None:
    config = RuleConfig.model_validate(
        {
            **VALID,
            "tenant_overrides": {
                "fcc": {"params": {"limit": 5}},
                "gfl": {"enabled": False},
            },
        }
    )
    assert config.params_for("fcc") == {"limit": 5, "strict": True}
    assert config.params_for("gfl") == {"limit": 3, "strict": True}
    assert config.params_for(None) == {"limit": 3, "strict": True}
    assert config.enabled_for("fcc") is True
    assert config.enabled_for("gfl") is False


def test_registry_mismatch_is_reported(tmp_path: Path) -> None:
    _write(tmp_path, VALID)
    problems = check_registry(load_rules(tmp_path), {"VA-E77": object()})
    assert problems == [
        "VA-E77: implementation without rules/VA-E77.yaml",
        "VA-F99: YAML without an implementation",
    ]


def test_rule_registered_twice_is_refused() -> None:
    async def other(_ctx: Any) -> list[Any]:
        return []

    with pytest.raises(RuntimeError, match="twice"):
        rule("VA-F01")(other)


def test_startup_validation(rules_dir_env: Any, tmp_path: Path, rules_copy: Path) -> None:
    rules_dir_env(rules_copy)
    assert set(validate_rules().rules) == P0_RULES

    _write(rules_copy, VALID)  # a YAML without implementation
    rules_dir_env(rules_copy)
    with pytest.raises(RuleConfigError, match="VA-F99: YAML without an implementation"):
        validate_rules()

    (rules_copy / "VA-F99.yaml").write_text("id: VA-F99\n", encoding="utf-8")
    rules_dir_env(rules_copy)
    with pytest.raises(RuleConfigError):
        validate_rules()

    rules_dir_env(tmp_path / "missing")  # an image built without rules/: logged, no rules
    assert validate_rules().rules == {}
    assert loader.rules_dir() == tmp_path / "missing"


def test_validate_rules_command(tmp_path: Path, rules_copy: Path) -> None:
    """VA-007 CI gate (`make check-api`): a rule without both fixtures fails."""
    from typer.testing import CliRunner

    from farmerapp.jobs.cli import cli

    runner = CliRunner()
    ok = runner.invoke(cli, ["validate-rules", "--rules-dir", str(DEFAULT_RULES_DIR)])
    assert ok.exit_code == 0, ok.output
    assert f"{len(P0_RULES)} rules OK" in ok.output

    no_fixtures = runner.invoke(cli, ["validate-rules", "--rules-dir", str(rules_copy)])
    assert no_fixtures.exit_code == 1
    assert "VA-F02: missing fixtures/VA-F02/negative.yaml" in no_fixtures.output

    _write(tmp_path, {**VALID, "mode": "nightly"})
    broken = runner.invoke(cli, ["validate-rules", "--rules-dir", str(tmp_path)])
    assert broken.exit_code == 1 and "invalid rule files" in broken.output


async def test_threshold_change_is_yaml_only(db_session: AsyncSession, rules_copy: Path) -> None:
    """VA-001 acceptance: the same records flag or not depending only on the YAML."""
    data = load_fixture("VA-F06", "positive")
    world, outcome = await run_fixture(db_session, "VA-F06", data, rule_set=load_rules(rules_copy))
    assert_expected(world, data, outcome)

    path = rules_copy / "VA-F06.yaml"
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    raw["version"] = 2
    raw["params"]["max_registrations"] = 12  # nine registrations are no longer a burst
    raw["params"]["max_officers_per_device"] = 2
    path.write_text(yaml.safe_dump(raw), encoding="utf-8")
    _world, relaxed = await run_fixture(db_session, "VA-F06", data, rule_set=load_rules(rules_copy))
    assert relaxed.report.rules_run == ["VA-F06"]
    assert relaxed.flags == []


async def test_tenant_override_and_disable(db_session: AsyncSession, rules_copy: Path) -> None:
    data = load_fixture("VA-F06", "positive")
    path = rules_copy / "VA-F06.yaml"
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    raw["tenant_overrides"] = {
        "strict-tenant": {"params": {"max_registrations": 4}},
        "quiet-tenant": {"enabled": False},
    }
    path.write_text(yaml.safe_dump(raw), encoding="utf-8")
    rule_set = load_rules(rules_copy)

    from tests.rules.harness import base_world

    quiet = await base_world(db_session, slug="quiet-tenant")
    _w, outcome = await run_fixture(db_session, "VA-F06", data, rule_set=rule_set, world=quiet)
    assert outcome.report.rules_run == [] and outcome.flags == []

    negative = load_fixture("VA-F06", "negative")  # 8 in 24 min: a burst for this tenant
    strict = await base_world(db_session, slug="strict-tenant")
    _w, outcome = await run_fixture(db_session, "VA-F06", negative, rule_set=rule_set, world=strict)
    assert [f.subject_id for f in outcome.flags] == [strict.refs["officer"]]
