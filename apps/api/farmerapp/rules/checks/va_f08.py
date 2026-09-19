"""VA-F08 — photo reuse across farmers: a farm or visit photo matches another farmer's photo.

* **Visit photos** carry the 64-bit perceptual hash (``visit_photo.phash``, 16 hex chars,
  FA-015). A photo of a visit to farmer A whose pHash is within ``max_hamming_distance``
  bits of a visit photo of *another* farmer B is the same field shown for two farmers.
  Hamming distance in SQL: ``bit_count(('x' || a)::bit(64) # ('x' || b)::bit(64))``.
* **Farm photos** (``farm_photo``, FA-012) have no pHash column yet (no migration in this
  change): they are matched by identical bytes (``sha256``, distance 0) against other
  farmers' farm and visit photos.

Event mode: ``visit.photo`` / ``visit.created`` (``ctx.subject_ids`` = visits: their photos
are checked) and ``farm.photo`` (= farms). The flag is farmer data (VA-003: store manager;
high severity also the auditors) about the farmer of the *new* photo; evidence: both photos
(blob URIs), both farmer ids, the distance. One flag per pair of photos (key
``photo:<new photo>:<other photo>``), at most ``max_matches_per_photo`` closest matches per
new photo. Same-farmer reuse is VA-E08's business (employee data).

Params: ``max_hamming_distance``, ``max_matches_per_photo``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from sqlalchemy import bindparam, text

from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject

# Visit photos of the subject visits vs. other farmers' visit photos, by pHash distance.
_VISIT_PHASH = text(
    """
    WITH mine AS (
        SELECT p.id, p.blob_uri, p.phash, v.farmer_id, v.id AS visit_id
        FROM visit_photo p JOIN visit v ON v.id = p.visit_id
        WHERE p.tenant_id = :tenant_id AND p.visit_id IN :ids
          AND p.deleted_at IS NULL AND v.deleted_at IS NULL
          AND p.phash ~ '^[0-9a-f]{16}$'
    ), ranked AS (
        SELECT m.id AS photo_id, m.blob_uri, m.farmer_id, m.visit_id,
               o.id AS other_id, o.blob_uri AS other_uri, ov.farmer_id AS other_farmer,
               ov.id AS other_visit,
               bit_count(('x' || m.phash)::bit(64) # ('x' || o.phash)::bit(64)) AS distance
        FROM mine m
        JOIN visit_photo o ON o.tenant_id = :tenant_id AND o.id <> m.id
             AND o.deleted_at IS NULL AND o.phash ~ '^[0-9a-f]{16}$'
        JOIN visit ov ON ov.id = o.visit_id AND ov.deleted_at IS NULL
             AND ov.farmer_id <> m.farmer_id
    )
    SELECT photo_id, blob_uri, farmer_id, 'visit_photo' AS kind, visit_id AS source_id,
           other_id, other_uri, other_farmer, 'visit_photo' AS other_kind,
           other_visit AS other_source_id, distance
    FROM ranked WHERE distance <= :max_distance
    ORDER BY photo_id, distance, other_id
    """
).bindparams(bindparam("ids", expanding=True))

# Farm photos of the subject farms / visit photos of the subject visits vs. other farmers'
# farm and visit photos with the same bytes.
_SHA_MATCHES = text(
    """
    WITH photos AS (
        SELECT fp.id, fp.blob_uri, fp.sha256, f.farmer_id, 'farm_photo' AS kind,
               f.id AS source_id
        FROM farm_photo fp JOIN farm f ON f.id = fp.farm_id
        WHERE fp.tenant_id = :tenant_id AND fp.deleted_at IS NULL AND f.deleted_at IS NULL
          AND fp.sha256 IS NOT NULL
        UNION ALL
        SELECT p.id, p.blob_uri, p.sha256, v.farmer_id, 'visit_photo', v.id
        FROM visit_photo p JOIN visit v ON v.id = p.visit_id
        WHERE p.tenant_id = :tenant_id AND p.deleted_at IS NULL AND v.deleted_at IS NULL
          AND p.sha256 IS NOT NULL
    )
    SELECT m.id, m.blob_uri, m.farmer_id, m.kind, m.source_id,
           o.id, o.blob_uri, o.farmer_id, o.kind, o.source_id, 0 AS distance
    FROM photos m
    JOIN photos o ON o.sha256 = m.sha256 AND o.farmer_id <> m.farmer_id AND o.id <> m.id
    WHERE m.source_id IN :ids
      AND (m.kind = 'farm_photo' OR o.kind = 'farm_photo')
    ORDER BY m.id, o.id
    """
).bindparams(bindparam("ids", expanding=True))


@dataclass(frozen=True)
class _Match:
    photo_id: uuid.UUID
    uri: str
    farmer: uuid.UUID
    kind: str
    source: uuid.UUID
    other_id: uuid.UUID
    other_uri: str
    other_farmer: uuid.UUID
    other_kind: str
    other_source: uuid.UUID
    distance: int


def _source_kind(kind: str) -> str:
    return "farm" if kind == "farm_photo" else "visit"


@rule("VA-F08")
async def check(ctx: RuleContext) -> list[Finding]:
    if not ctx.subject_ids:
        return []  # event rule: the event names the visits / farms
    params = {
        "tenant_id": ctx.tenant_id,
        "ids": list(ctx.subject_ids),
        "max_distance": int(ctx.param("max_hamming_distance")),
    }
    limit = int(ctx.param("max_matches_per_photo"))
    matches: list[_Match] = []
    for stmt in (_VISIT_PHASH, _SHA_MATCHES):
        rows = await ctx.session.execute(stmt, params)
        matches += [_Match(*row) for row in rows.tuples()]
    per_photo: dict[uuid.UUID, dict[uuid.UUID, _Match]] = {}
    for match in sorted(matches, key=lambda m: (m.distance, str(m.other_id))):
        chosen = per_photo.setdefault(match.photo_id, {})
        if match.other_id not in chosen and len(chosen) < limit:
            chosen[match.other_id] = match
    findings: list[Finding] = []
    for photo_id in sorted(per_photo, key=str):
        for match in per_photo[photo_id].values():
            findings.append(
                Finding(
                    subject_type=Subject.FARMER,
                    subject_id=match.farmer,
                    key=f"photo:{photo_id}:{match.other_id}",
                    title=(
                        "Photo matches another farmer's photo"
                        + (" (same image)" if match.distance == 0 else f" ({match.distance} bits)")
                    ),
                    evidence=Evidence(
                        records=[
                            record("farmer", match.farmer),
                            record(match.kind, photo_id),
                            record(_source_kind(match.kind), match.source),
                            record("farmer", match.other_farmer),
                            record(match.other_kind, match.other_id),
                            record(_source_kind(match.other_kind), match.other_source),
                        ],
                        photos=[match.uri, match.other_uri],
                        metrics={
                            "reason": "photo_reuse",
                            "hamming_distance": match.distance,
                            "max_hamming_distance": params["max_distance"],
                            "farmer_id": str(match.farmer),
                            "other_farmer_id": str(match.other_farmer),
                            "match": "sha256"
                            if match.kind == "farm_photo" or match.other_kind == "farm_photo"
                            else "phash",
                        },
                    ),
                )
            )
    return findings
