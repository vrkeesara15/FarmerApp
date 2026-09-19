"""VA-007: every rule ships a positive and a negative golden fixture, and both pass.

``test_every_rule_has_both_fixtures`` enumerates the rule YAML files *and* the registered
implementations, so a new rule without ``rules/fixtures/<id>/{positive,negative}.yaml``
fails CI. ``test_golden_fixture`` seeds each fixture into a fresh tenant, runs the rule
through the real engine and compares the flags with ``expect``; a batch fixture is run twice
to prove re-runs never duplicate an open flag.
"""

from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.rules.loader import DEFAULT_RULES_DIR, load_rules
from farmerapp.rules.registry import implementations
from farmerapp.rules.schema import Mode
from tests.rules.harness import (
    ALL_RULES,
    CASES,
    FIXTURES_DIR,
    P0_RULES,
    assert_expected,
    case_sign,
    fixture_cases,
    fixture_path,
    load_fixture,
    run_fixture,
)

RULE_SET = load_rules(DEFAULT_RULES_DIR)
RULE_IDS = sorted(set(RULE_SET.rules) | set(implementations()))
PAIRS = [(rule_id, case) for rule_id in RULE_IDS for case in fixture_cases(rule_id)]


def test_rules_exist() -> None:
    """Every rule of SPEC 6.2 / 6.3 — the eleven P0 rules of M4 and the ten of M7 — is
    configured and implemented, and nothing else is."""
    assert len(ALL_RULES) == 21 and P0_RULES <= ALL_RULES
    assert set(RULE_SET.rules) == ALL_RULES
    assert set(implementations()) == ALL_RULES


@pytest.mark.parametrize("rule_id", RULE_IDS)
def test_every_rule_has_both_fixtures(rule_id: str) -> None:
    for case in CASES:
        assert fixture_path(rule_id, case).is_file(), (
            f"{rule_id} has no {case} fixture: add rules/fixtures/{rule_id}/{case}.yaml (VA-007)"
        )


def test_no_orphan_fixtures() -> None:
    orphans = [p.name for p in FIXTURES_DIR.iterdir() if p.is_dir() and p.name not in RULE_IDS]
    assert orphans == []


@pytest.mark.parametrize(("rule_id", "case"), PAIRS, ids=[f"{r}-{c}" for r, c in PAIRS])
def test_fixture_expectations_have_the_right_sign(rule_id: str, case: str) -> None:
    flags = load_fixture(rule_id, case)["expect"]["flags"]
    if case_sign(case) == "positive":
        assert flags, "a positive case must flag"
    else:
        assert flags == [], "a negative must not"


def test_extra_fixture_cases_are_named_by_sign() -> None:
    """Extra scenarios are ``positive-<name>`` / ``negative-<name>``; anything else in a
    rule's fixture directory would silently never run."""
    for rule_id in RULE_IDS:
        for path in (FIXTURES_DIR / rule_id).glob("*"):
            assert path.stem in fixture_cases(rule_id), f"unrecognised fixture {path}"
    assert "positive-farm-photo" in fixture_cases("VA-F08")
    assert "negative-no-campaigns" in fixture_cases("VA-F09")
    assert "positive-repeated" in fixture_cases("VA-E10")


@pytest.mark.parametrize(("rule_id", "case"), PAIRS, ids=[f"{r}-{c}" for r, c in PAIRS])
async def test_golden_fixture(db_session: AsyncSession, rule_id: str, case: str) -> None:
    data = load_fixture(rule_id, case)
    world, outcome = await run_fixture(db_session, rule_id, data, rule_set=RULE_SET)
    assert rule_id in outcome.report.rules_run
    assert_expected(world, data, outcome)
    for flag in outcome.flags:
        assert flag.rule_version == RULE_SET.get(rule_id).version
        assert flag.evidence["records"], "every flag cites the records it is about"
        assert flag.sla_due_at > flag.created_at
    if Mode(data.get("mode", "batch")) == Mode.BATCH:
        _world, rerun = await run_fixture(
            db_session, rule_id, {**data, "seed": {}}, rule_set=RULE_SET, world=world
        )
        assert rerun.report.total_raised == 0
        assert len(rerun.flags) == len(outcome.flags)
