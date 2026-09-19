"""VA-E08 — photo integrity of a visit's in-app photos.

* **EXIF inconsistent with the check-in**: the write path (FA-015, ``visits.service.add_photo``)
  compares each photo's EXIF time with the visit window (± 30 min) and its EXIF GPS with the
  check-in point (300 m) and records ``exif_time_mismatch`` / ``exif_gps_mismatch`` in
  ``visit_photo.photo_flags``; the rule turns those into a flag. Missing EXIF
  (``exif_*_missing``) flags only with ``flag_missing_exif: true``.
* **Reused photo**: the same bytes (``sha256``) or the same perceptual hash as a photo of
  *another visit* (any officer, any farmer). The write path marks the later upload
  ``duplicate_photo``; the rule looks the other visit up again, so the evidence cites it and
  a reuse is caught whichever photo arrived first. Near-duplicates across *farmers* are
  VA-F08's (farmer data) business.

Event mode on ``visit.photo`` / ``visit.checked_out`` / ``visit.created``
(``ctx.subject_ids`` = visits). One flag per visit (key ``visit:<id>``) about its officer.

Params: ``flag_missing_exif``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import or_, select
from sqlalchemy.orm import aliased

from farmerapp.rules.checks.common import geo_point
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.visits.models import (
    PHOTO_FLAG_DUPLICATE,
    PHOTO_FLAG_EXIF_GPS_MISMATCH,
    PHOTO_FLAG_EXIF_GPS_MISSING,
    PHOTO_FLAG_EXIF_TIME_MISMATCH,
    PHOTO_FLAG_EXIF_TIME_MISSING,
    Visit,
    VisitPhoto,
)

INCONSISTENT = (PHOTO_FLAG_EXIF_TIME_MISMATCH, PHOTO_FLAG_EXIF_GPS_MISMATCH)
MISSING = (PHOTO_FLAG_EXIF_TIME_MISSING, PHOTO_FLAG_EXIF_GPS_MISSING)


@dataclass
class _VisitPhotos:
    officer: uuid.UUID
    lon: float
    lat: float
    reasons: set[str] = field(default_factory=set)
    photos: dict[uuid.UUID, str] = field(default_factory=dict)  # id -> blob uri
    exif_points: list[dict[str, Any]] = field(default_factory=list)
    reused: dict[uuid.UUID, list[dict[str, str]]] = field(default_factory=dict)


@rule("VA-E08")
async def check(ctx: RuleContext) -> list[Finding]:
    if not ctx.subject_ids:
        return []  # event rule: the event names the visits
    wanted = set(INCONSISTENT) | ({*MISSING} if ctx.param("flag_missing_exif") else set())
    rows = await ctx.session.execute(
        select(
            Visit.id,
            Visit.officer_id,
            Visit.checkin_lon,
            Visit.checkin_lat,
            VisitPhoto.id,
            VisitPhoto.blob_uri,
            VisitPhoto.photo_flags,
            VisitPhoto.exif_lon,
            VisitPhoto.exif_lat,
        )
        .join(VisitPhoto, VisitPhoto.visit_id == Visit.id)
        .where(
            Visit.tenant_id == ctx.tenant_id,
            Visit.id.in_(ctx.subject_ids),
            Visit.deleted_at.is_(None),
            VisitPhoto.deleted_at.is_(None),
        )
        .order_by(Visit.id, VisitPhoto.created_at, VisitPhoto.id)
    )
    visits: dict[uuid.UUID, _VisitPhotos] = {}
    for visit_id, officer, lon, lat, photo_id, uri, flags, exif_lon, exif_lat in rows.tuples():
        entry = visits.setdefault(visit_id, _VisitPhotos(officer=officer, lon=lon, lat=lat))
        found = set(flags or []) & wanted
        if found:
            entry.reasons |= found
            entry.photos[photo_id] = uri
            if exif_lon is not None and exif_lat is not None:
                entry.exif_points.append(geo_point(exif_lon, exif_lat))

    # Reuse: the same sha256 / pHash on a photo of another visit.
    mine, other = aliased(VisitPhoto), aliased(VisitPhoto)
    reuse = await ctx.session.execute(
        select(mine.visit_id, mine.id, mine.blob_uri, other.visit_id, other.id, other.blob_uri)
        .join(
            other,
            (other.tenant_id == mine.tenant_id)
            & (other.visit_id != mine.visit_id)
            & or_(
                (other.sha256 == mine.sha256) & mine.sha256.is_not(None),
                (other.phash == mine.phash) & mine.phash.is_not(None),
            ),
        )
        .where(
            mine.tenant_id == ctx.tenant_id,
            mine.visit_id.in_(ctx.subject_ids),
            mine.deleted_at.is_(None),
            other.deleted_at.is_(None),
        )
        .order_by(mine.id, other.created_at, other.id)
    )
    for visit_id, photo_id, uri, other_visit, other_photo, other_uri in reuse.tuples():
        holder = visits.get(visit_id)
        if holder is None:  # pragma: no cover - a photo row always joins its visit above
            continue
        holder.reasons.add(PHOTO_FLAG_DUPLICATE)
        holder.photos[photo_id] = uri
        holder.photos.setdefault(other_photo, other_uri)
        holder.reused.setdefault(photo_id, []).append(
            {"photo_id": str(other_photo), "visit_id": str(other_visit)}
        )

    findings: list[Finding] = []
    for visit_id, entry in sorted(visits.items(), key=lambda kv: str(kv[0])):
        if not entry.reasons:
            continue
        reasons = sorted(entry.reasons)
        other_visits = sorted({r["visit_id"] for matches in entry.reused.values() for r in matches})
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=entry.officer,
                key=f"visit:{visit_id}",
                title="Visit photo integrity: " + ", ".join(r.replace("_", " ") for r in reasons),
                evidence=Evidence(
                    records=[record("user", entry.officer), record("visit", visit_id)]
                    + [record("visit_photo", p) for p in entry.photos]
                    + [record("visit", v) for v in other_visits],
                    points=[geo_point(entry.lon, entry.lat), *entry.exif_points],
                    photos=list(entry.photos.values()),
                    metrics={
                        "reasons": reasons,
                        "reused": {str(k): v for k, v in entry.reused.items()},
                    },
                ),
            )
        )
    return findings
