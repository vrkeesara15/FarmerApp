"""DX-003 decision rule — a pure function of the kNN neighbours and the thresholds.

``decide(neighbours, thresholds)``:

* ``top1`` = cosine similarity of the nearest corpus image; its problem is the proposal;
* ``agreement`` = share of the top-10 neighbours (fewer if the corpus is smaller) whose
  problem is the proposal;
* **high** when ``top1 >= T1`` **and** ``agreement >= 60 %`` (per-crop, versioned thresholds)
  -> the corpus answers;
* **medium** when one of the two holds, **low** otherwise -> the LLM fallback (DX-004) and a
  provisional answer for the agronomist queue;
* ``in_scope`` is false when even the nearest image is below ``min_similarity`` (DX-010:
  nothing in the corpus looks like this photo — not a plant, or an unsupported crop).

``candidates`` are the top-5 distinct problems by their best similarity (the LLM must choose
among them or answer "unknown"). Because the function is pure and its inputs are stored on
the diagnosis (``scores``), any result can be re-derived from stored data (DX-005).
"""

from __future__ import annotations

import uuid
from collections import Counter
from dataclasses import asdict, dataclass, field
from typing import Any

from farmerapp.diagnosis.models import Confidence

#: Defaults when a tenant has no ``diagnosis_threshold`` row (config version 0). Tuned for the
#: fake pixel encoder on the synthetic seed (docs/prs/M6-diagnosis-api.md); the agronomist /
#: ML retune them per crop for the real encoder from the ml/eval report (human gate).
DEFAULT_T1 = 0.92
DEFAULT_AGREEMENT = 0.6
DEFAULT_MIN_SIMILARITY = 0.85
TOP_AGREEMENT = 10
MAX_CANDIDATES = 5


@dataclass(frozen=True)
class Thresholds:
    t1: float = DEFAULT_T1
    agreement: float = DEFAULT_AGREEMENT
    min_similarity: float = DEFAULT_MIN_SIMILARITY
    config_version: int = 0  # 0 = built-in defaults
    crop_id: uuid.UUID | None = None

    def to_json(self) -> dict[str, Any]:
        return {
            "t1": self.t1,
            "agreement": self.agreement,
            "min_similarity": self.min_similarity,
            "config_version": self.config_version,
            "crop_id": str(self.crop_id) if self.crop_id else None,
        }

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Thresholds:
        crop = data.get("crop_id")
        return cls(
            t1=float(data["t1"]),
            agreement=float(data["agreement"]),
            min_similarity=float(data["min_similarity"]),
            config_version=int(data.get("config_version", 0)),
            crop_id=uuid.UUID(crop) if crop else None,
        )


@dataclass(frozen=True)
class Neighbour:
    image_id: uuid.UUID
    problem_id: uuid.UUID
    similarity: float

    def to_json(self) -> dict[str, Any]:
        return {
            "image_id": str(self.image_id),
            "problem_id": str(self.problem_id),
            "similarity": round(self.similarity, 6),
        }

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Neighbour:
        return cls(
            image_id=uuid.UUID(data["image_id"]),
            problem_id=uuid.UUID(data["problem_id"]),
            similarity=float(data["similarity"]),
        )


@dataclass(frozen=True)
class Candidate:
    problem_id: uuid.UUID
    score: float  # best similarity of the problem's images
    votes: int  # neighbours of the problem among the top-10


@dataclass(frozen=True)
class Decision:
    confidence: Confidence
    problem_id: uuid.UUID | None  # the corpus proposal (top-1's problem)
    top1: float
    agreement: float
    votes: dict[str, int]
    in_scope: bool
    candidates: list[Candidate] = field(default_factory=list)

    @property
    def high(self) -> bool:
        return self.confidence == Confidence.HIGH

    def to_json(self) -> dict[str, Any]:
        out = asdict(self)
        out["confidence"] = self.confidence.value
        out["problem_id"] = str(self.problem_id) if self.problem_id else None
        out["candidates"] = [
            {"problem_id": str(c.problem_id), "score": round(c.score, 6), "votes": c.votes}
            for c in self.candidates
        ]
        out["top1"] = round(self.top1, 6)
        out["agreement"] = round(self.agreement, 6)
        return out


def decide(neighbours: list[Neighbour], thresholds: Thresholds) -> Decision:
    """The DX-003 decision for ``neighbours`` (any order; sorted here, nearest first)."""
    ranked = sorted(neighbours, key=lambda n: (-n.similarity, str(n.image_id)))
    if not ranked:
        return Decision(
            confidence=Confidence.LOW,
            problem_id=None,
            top1=0.0,
            agreement=0.0,
            votes={},
            in_scope=False,
        )
    top = ranked[0]
    window = ranked[:TOP_AGREEMENT]
    votes = Counter(str(n.problem_id) for n in window)
    agreement = votes[str(top.problem_id)] / len(window)
    strong_match = top.similarity >= thresholds.t1
    agreed = agreement >= thresholds.agreement
    if strong_match and agreed:
        confidence = Confidence.HIGH
    elif strong_match or agreed:
        confidence = Confidence.MEDIUM
    else:
        confidence = Confidence.LOW
    best: dict[uuid.UUID, float] = {}
    for n in ranked:
        best.setdefault(n.problem_id, n.similarity)
    candidates = [
        Candidate(problem_id=p, score=s, votes=votes.get(str(p), 0))
        for p, s in sorted(best.items(), key=lambda kv: (-kv[1], str(kv[0])))
    ][:MAX_CANDIDATES]
    return Decision(
        confidence=confidence,
        problem_id=top.problem_id,
        top1=top.similarity,
        agreement=agreement,
        votes=dict(sorted(votes.items())),
        in_scope=top.similarity >= thresholds.min_similarity,
        candidates=candidates,
    )


def replay(scores: dict[str, Any]) -> Decision:
    """DX-005: the decision re-derived from a diagnosis' stored ``scores``."""
    neighbours = [Neighbour.from_json(n) for n in scores.get("neighbours", [])]
    return decide(neighbours, Thresholds.from_json(scores["thresholds"]))


__all__ = [
    "DEFAULT_AGREEMENT",
    "DEFAULT_MIN_SIMILARITY",
    "DEFAULT_T1",
    "MAX_CANDIDATES",
    "TOP_AGREEMENT",
    "Candidate",
    "Decision",
    "Neighbour",
    "Thresholds",
    "decide",
    "replay",
]
