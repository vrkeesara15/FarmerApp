"""VA-F08 — photo reuse across farmers: a farm or visit photo matches another farmer's photo.

Every farm photo (``farm_photo.phash``, Alembic 0023; filled on attach and by
``backfill-farm-photo-phash``) and visit photo (``visit_photo.phash``, FA-015) carries the
64-bit perceptual hash (16 hex chars, ``visits.photos.phash``). A new photo of farmer A
matches a photo of *another* farmer B when

* both have a pHash and the Hamming distance is within ``max_hamming_distance`` bits (the
  same field re-encoded, resized or slightly cropped), in SQL:
  ``bit_count(('x' || a)::bit(64) # ('x' || b)::bit(64))``; or
* the bytes are identical (same ``sha256``; distance 0), which also covers rows whose pHash
  is not computed (an undecodable blob, a farm photo not backfilled yet).

Farm and visit photos are compared in both directions (farm vs farm, farm vs visit, visit vs
visit). Event mode: ``visit.photo`` / ``visit.created`` (``ctx.subject_ids`` = visits: their
photos are checked) and ``farm.photo`` (= farms). The flag is farmer data (VA-003: store
manager; high severity also the auditors) about the farmer of the *new* photo; evidence:
both photos (blob URIs), both farmer ids, the distance and how they matched (``phash`` /
``sha256``). One flag per pair of photos (key ``photo:<new photo>:<other photo>``), at most
``max_matches_per_photo`` closest matches per new photo. Same-farmer reuse is VA-E08's
business (employee data).

Params: ``max_hamming_distance``, ``max_matches_per_photo``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from sqlalchemy import bindparam, text

from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject

# Photos of the subject visits / farms vs. other farmers' farm and visit photos: identical
# bytes, or pHash within the distance.
_MATCHES = text(
    """
    WITH photos AS (
        SELECT fp.id, fp.blob_uri, fp.sha256,
               CASE WHEN fp.phash ~ '^[0-9a-f]{16}$' THEN fp.phash END AS phash,
               f.farmer_id, 'farm_photo' AS kind, f.id AS source_id
        FROM farm_photo fp JOIN farm f ON f.id = fp.farm_id
        WHERE fp.tenant_id = :tenant_id AND fp.deleted_at IS NULL AND f.deleted_at IS NULL
        UNION ALL
        SELECT p.id, p.blob_uri, p.sha256,
               CASE WHEN p.phash ~ '^[0-9a-f]{16}$' THEN p.phash END,
               v.farmer_id, 'visit_photo', v.id
        FROM visit_photo p JOIN visit v ON v.id = p.visit_id
        WHERE p.tenant_id = :tenant_id AND p.deleted_at IS NULL AND v.deleted_at IS NULL
    ), mine AS (
        SELECT * FROM photos WHERE source_id IN :ids
    ), pairs AS (
        SELECT m.id AS photo_id, m.blob_uri, m.farmer_id, m.kind, m.source_id,
               o.id AS other_id, o.blob_uri AS other_uri, o.farmer_id AS other_farmer,
               o.kind AS other_kind, o.source_id AS other_source,
               (m.sha256 IS NOT NULL AND o.sha256 = m.sha256) AS same_bytes,
               CASE WHEN m.phash IS NOT NULL AND o.phash IS NOT NULL
                    THEN bit_count(('x' || m.phash)::bit(64) # ('x' || o.phash)::bit(64))
               END AS phash_distance
        FROM mine m
        JOIN photos o ON o.id <> m.id AND o.farmer_id <> m.farmer_id
             AND ((m.sha256 IS NOT NULL AND o.sha256 = m.sha256)
                  OR (m.phash IS NOT NULL AND o.phash IS NOT NULL))
    )
    SELECT photo_id, blob_uri, farmer_id, kind, source_id,
           other_id, other_uri, other_farmer, other_kind, other_source,
           coalesce(phash_distance, 0) AS distance,
           CASE WHEN phash_distance IS NULL THEN 'sha256' ELSE 'phash' END AS matched_by
    FROM pairs
    WHERE same_bytes OR phash_distance <= :max_distance
    ORDER BY photo_id, distance, other_id
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
    matched_by: str


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
    rows = await ctx.session.execute(_MATCHES, params)
    matches = [_Match(*row) for row in rows.tuples()]
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
                            "match": match.matched_by,
                        },
                    ),
                )
            )
    return findings
