"""DX-003 decision rule and DX-005 replay (pure functions)."""

from __future__ import annotations

import random
import uuid

import pytest

from farmerapp.diagnosis.decision import (
    MAX_CANDIDATES,
    Neighbour,
    Thresholds,
    decide,
    replay,
)
from farmerapp.diagnosis.models import Confidence

A, B, C = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()


def _n(problem: uuid.UUID, similarity: float) -> Neighbour:
    return Neighbour(image_id=uuid.uuid4(), problem_id=problem, similarity=similarity)


def test_high_needs_top1_above_t1_and_60_percent_agreement() -> None:
    th = Thresholds(t1=0.9, agreement=0.6, min_similarity=0.5)
    neighbours = [_n(A, 0.95)] + [_n(A, 0.9 - i / 100) for i in range(5)] + [_n(B, 0.7)] * 4
    decision = decide(neighbours, th)
    assert decision.confidence == Confidence.HIGH
    assert decision.problem_id == A
    assert decision.agreement == pytest.approx(0.6)
    assert decision.in_scope
    assert decision.votes == {str(A): 6, str(B): 4}


def test_medium_when_only_one_condition_holds() -> None:
    th = Thresholds(t1=0.9, agreement=0.6, min_similarity=0.5)
    split = [_n(A, 0.95), _n(B, 0.94), _n(C, 0.93), _n(A, 0.8), _n(B, 0.8)]
    assert decide(split, th).confidence == Confidence.MEDIUM  # strong match, no agreement
    weak = [_n(A, 0.85)] * 10
    assert decide(weak, th).confidence == Confidence.MEDIUM  # agreement, weak match


def test_low_and_out_of_scope() -> None:
    th = Thresholds(t1=0.9, agreement=0.6, min_similarity=0.5)
    low = [_n(A, 0.6), _n(B, 0.59), _n(C, 0.58)]
    decision = decide(low, th)
    assert decision.confidence == Confidence.LOW and decision.in_scope
    far = decide([_n(A, 0.3)], th)
    assert not far.in_scope
    empty = decide([], th)
    assert empty.problem_id is None and not empty.in_scope and empty.candidates == []


def test_candidates_are_the_top_five_distinct_problems_by_best_score() -> None:
    problems = [uuid.uuid4() for _ in range(8)]
    neighbours = [_n(p, 0.9 - i * 0.01) for i, p in enumerate(problems)] + [_n(problems[0], 0.5)]
    decision = decide(neighbours, Thresholds())
    assert [c.problem_id for c in decision.candidates] == problems[:MAX_CANDIDATES]
    assert decision.candidates[0].score == pytest.approx(0.9)


def test_order_of_input_does_not_matter() -> None:
    rng = random.Random(7)
    neighbours = [_n(rng.choice([A, B, C]), rng.uniform(0.5, 1.0)) for _ in range(20)]
    shuffled = neighbours[:]
    rng.shuffle(shuffled)
    assert decide(neighbours, Thresholds()) == decide(shuffled, Thresholds())


@pytest.mark.parametrize("seed", range(25))
def test_replay_from_stored_scores_reproduces_the_decision(seed: int) -> None:
    """DX-005: the stored neighbours + thresholds re-derive the same answer."""
    rng = random.Random(seed)
    th = Thresholds(
        t1=rng.uniform(0.7, 0.99),
        agreement=rng.uniform(0.3, 0.9),
        min_similarity=0.2,
        config_version=rng.randint(0, 5),
        crop_id=uuid.uuid4(),
    )
    neighbours = [_n(rng.choice([A, B, C]), rng.uniform(0.1, 1.0)) for _ in range(20)]
    decision = decide(neighbours, th)
    stored = {"neighbours": [n.to_json() for n in neighbours], "thresholds": th.to_json()}
    again = replay(stored)
    assert again.to_json() == decision.to_json()
