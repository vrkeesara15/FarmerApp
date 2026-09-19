"""VA-F02 — duplicate farmer: the same phone, or a similar name in the same village with farm
centroids within ``centroid_distance_m``.

``(tenant, phone)`` is unique, so "same phone" means the same last ten digits written
differently (an import with ``9876543210`` next to ``+919876543210``). The fuzzy branch pairs
farmers of one village whose ``pg_trgm`` ``similarity(name, name) >= name_similarity`` and
then looks for their two closest farms with ``ST_DWithin`` on the generated ``farm.centroid``
(GiST index). Pairing inside a village keeps the nightly batch linear in practice.

One flag per pair (the dedupe key is the sorted pair), about the more recently registered
farmer — the likely duplicate — with both farmers and the two closest farms as evidence.

Params: ``name_similarity`` (0..1), ``centroid_distance_m``.
"""

from __future__ import annotations

import json
from typing import Any

from sqlalchemy import Float, Select, and_, cast, func, select, true
from sqlalchemy.orm import aliased

from farmerapp.farmers.models import Farm, Farmer
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject


def _digits10(column: Any) -> Any:
    return func.right(func.regexp_replace(column, r"\D", "", "g"), 10)


def _pair(first: Farmer, second: Farmer) -> tuple[Farmer, Farmer, str]:
    newer, older = (
        (first, second)
        if (first.created_at, str(first.id)) >= (second.created_at, str(second.id))
        else (second, first)
    )
    return newer, older, "|".join(sorted((str(first.id), str(second.id))))


def _finding(
    newer: Farmer,
    older: Farmer,
    key: str,
    *,
    reason: str,
    similarity: float | None,
    farms: Any = None,
) -> Finding:
    records = [record("farmer", newer.id), record("farmer", older.id)]
    points: list[dict[str, Any]] = []
    distance = None
    if farms is not None:
        records += [record("farm", farms.farm_a), record("farm", farms.farm_b)]
        points = [json.loads(farms.point_a), json.loads(farms.point_b)]
        distance = round(float(farms.distance_m), 1)
    return Finding(
        subject_type=Subject.FARMER,
        subject_id=newer.id,
        key=key,
        title=f"Possible duplicate of farmer {older.name}",
        evidence=Evidence(
            records=records,
            points=points,
            metrics={
                "reason": reason,
                "name_similarity": round(similarity, 3) if similarity is not None else None,
                "centroid_distance_m": distance,
                "same_village": newer.village_id == older.village_id,
            },
        ),
    )


def _scoped(stmt: Select[Any], a: Any, ctx: RuleContext) -> Select[Any]:
    stmt = stmt.where(a.tenant_id == ctx.tenant_id, a.deleted_at.is_(None))
    if ctx.subject_ids is not None:
        stmt = stmt.where(a.id.in_(ctx.subject_ids))
    return stmt


@rule("VA-F02")
async def check(ctx: RuleContext) -> list[Finding]:
    threshold = float(ctx.param("name_similarity"))
    distance_m = float(ctx.param("centroid_distance_m"))
    a, b = aliased(Farmer), aliased(Farmer)
    findings: dict[str, Finding] = {}

    same_phone = _scoped(
        select(a, b).join(
            b,
            and_(
                b.tenant_id == a.tenant_id,
                b.id != a.id,
                b.deleted_at.is_(None),
                _digits10(b.phone) == _digits10(a.phone),
            ),
        ),
        a,
        ctx,
    )
    for first, second in (await ctx.session.execute(same_phone)).tuples():
        newer, older, key = _pair(first, second)
        findings.setdefault(key, _finding(newer, older, key, reason="same_phone", similarity=None))

    fa, fb = aliased(Farm), aliased(Farm)
    similarity = func.similarity(a.name, b.name)
    close = (
        select(
            fa.id.label("farm_a"),
            fb.id.label("farm_b"),
            cast(func.ST_Distance(fa.centroid, fb.centroid), Float).label("distance_m"),
            func.ST_AsGeoJSON(fa.centroid).label("point_a"),
            func.ST_AsGeoJSON(fb.centroid).label("point_b"),
        )
        .select_from(fa)
        .join(fb, func.ST_DWithin(fa.centroid, fb.centroid, distance_m))
        .where(
            fa.farmer_id == a.id,
            fb.farmer_id == b.id,
            fa.deleted_at.is_(None),
            fb.deleted_at.is_(None),
        )
        .order_by(func.ST_Distance(fa.centroid, fb.centroid))
        .limit(1)
        .lateral("close")
    )
    fuzzy = _scoped(
        select(a, b, similarity.label("similarity"), close)
        .join(
            b,
            and_(
                b.tenant_id == a.tenant_id,
                b.village_id == a.village_id,
                b.id != a.id,
                b.deleted_at.is_(None),
                similarity >= threshold,
            ),
        )
        .join(close, true()),
        a,
        ctx,
    )
    for row in (await ctx.session.execute(fuzzy)).all():
        newer, older, key = _pair(row[0], row[1])
        findings.setdefault(
            key,
            _finding(
                newer,
                older,
                key,
                reason="similar_name_nearby_farm",
                similarity=float(row.similarity),
                farms=row,
            ),
        )
    return list(findings.values())
