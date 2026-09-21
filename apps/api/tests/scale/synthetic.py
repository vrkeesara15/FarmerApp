"""NF-007: a synthetic tenant at 1/50th of the scale target, built with set-based SQL.

SPEC 7 asks for 50 tenants, 5,000 officers, 2 million farmers and 20 million photos. One
fiftieth of that is one tenant with 100 officers, 40,000 farmers and 400,000 photo rows —
big enough that every query plan that is O(tenant size) shows itself, small enough to seed in
under two minutes on a laptop so the suite is actually run.

The rows are generated with ``INSERT ... SELECT ... FROM generate_series`` rather than the ORM:
40,000 mapped objects would measure SQLAlchemy, not Postgres, and would take minutes. Every
insert runs as the ordinary app role inside the tenant's binding, so RLS applies exactly as it
does in production — which is itself part of what the suite proves (the ``WITH CHECK`` on
every policy is enforced 840,000 times here).

The shape mirrors the pilot: one farm per farmer, one visit per farmer, ten photos per visit
(20 million photos / 2 million farmers = 10), a diagnosis for one farmer in two and an order
for one in two, and a week of location points for every officer.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

#: 1/50th of the NF-007 target.
OFFICERS = 100
FARMERS = 40_000
PHOTOS_PER_VISIT = 10
DIAGNOSIS_SHARE = 2  # one farmer in two
ORDER_SHARE = 2
LOCATION_DAYS = 7
POINTS_PER_OFFICER_DAY = 150  # VV-001 sampling at 120 s while moving

#: Where the synthetic tenant lives (Warangal, like the pilot's first store).
BASE_LAT, BASE_LON = 17.9784, 79.6003


@dataclass(frozen=True)
class ScaleData:
    tenant_id: uuid.UUID
    officers: list[uuid.UUID]
    farmers: int
    visits: int
    photos: int
    diagnoses: int
    orders: int
    location_points: int
    seconds: float


async def _scalar(session: AsyncSession, sql: str, **params: object) -> int:
    value = await session.scalar(text(sql), params)
    return int(value or 0)


async def _count(session: AsyncSession, table: str, tenant_id: uuid.UUID) -> int:
    return await _scalar(
        session,
        f'SELECT count(*) FROM "{table}" WHERE tenant_id = :tid',  # nosec B608 - fixed names
        tid=tenant_id,
    )


async def build(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    officers: list[uuid.UUID],
    villages: list[uuid.UUID],
    stores: list[uuid.UUID],
    farmers: int = FARMERS,
    now: datetime | None = None,
) -> ScaleData:
    """Fill ``tenant_id`` to scale. The session must be bound to it and will be committed."""
    started = datetime.now(UTC)
    moment = now or started
    marker = "scale"
    common = {
        "tid": tenant_id,
        "officers": [str(o) for o in officers],
        "villages": [str(v) for v in villages],
        "stores": [str(s) for s in stores],
        "n": farmers,
        "now": moment,
    }

    # -------------------------------------------------------------- farmers
    await session.execute(
        text(
            """
INSERT INTO farmer (id, tenant_id, created_at, updated_at, version, phone, phone_last4,
                    name, village_id, language, consent_marketing, source, phone_verified,
                    registered_by)
SELECT gen_random_uuid(), :tid,
       CAST(:now AS timestamptz) - (g * interval '1 minute'),
       CAST(:now AS timestamptz), 1,
       '+9198' || lpad(g::text, 8, '0'),
       lpad((g % 10000)::text, 4, '0'),
       'Scale Farmer ' || g,
       (CAST(:villages AS uuid[]))[1 + (g % array_length(CAST(:villages AS uuid[]), 1))],
       'te', (g % 3 = 0), 'officer', false,
       -- SPEC 2.6: a field officer only sees the farmers they registered, so the synthetic
       -- tenant has to say who registered each one or every officer-scoped read is empty.
       (CAST(:officers AS uuid[]))[1 + (g % array_length(CAST(:officers AS uuid[]), 1))]
FROM generate_series(1, :n) AS g
"""
        ),
        common,
    )

    # -------------------------------------------------------------- farms
    await session.execute(
        text(
            """
INSERT INTO farm (id, tenant_id, created_at, updated_at, version, farmer_id, name, area_acres)
SELECT gen_random_uuid(), :tid, f.created_at, CAST(:now AS timestamptz), 1, f.id, 'Scale farm', 2.00
FROM farmer f
WHERE f.tenant_id = :tid AND f.name LIKE 'Scale Farmer %'
"""
        ),
        common,
    )

    # -------------------------------------------------------------- visits
    await session.execute(
        text(
            """
INSERT INTO visit (id, tenant_id, created_at, updated_at, version, officer_id, farmer_id,
                   purpose, checkin_at, checkout_at, checkin_point, geofence_result, status,
                   confirmation_channel, device_integrity, flags, notes)
SELECT gen_random_uuid(), :tid, f.created_at, CAST(:now AS timestamptz), 1,
       coalesce(f.registered_by, (CAST(:officers AS uuid[]))[1]),
       f.id, 'advisory', f.created_at, f.created_at + interval '12 minutes',
       ST_SetSRID(ST_MakePoint(:lon + (random() - 0.5) * 0.2,
                               :lat + (random() - 0.5) * 0.2), 4326)::geography,
       'inside', 'verified', 'sms_otp', '{}'::jsonb, '[]'::jsonb, 'Scale visit'
FROM farmer f
WHERE f.tenant_id = :tid AND f.name LIKE 'Scale Farmer %'
"""
        ),
        {**common, "lat": BASE_LAT, "lon": BASE_LON},
    )

    # -------------------------------------------------------------- photos
    await session.execute(
        text(
            """
INSERT INTO visit_photo (id, tenant_id, created_at, updated_at, version, visit_id, blob_uri,
                         sha256, taken_in_app, server_time, photo_flags)
SELECT gen_random_uuid(), :tid, v.created_at, CAST(:now AS timestamptz), 1, v.id,
       'gs://scale/' || v.id || '/' || p || '.jpg',
       encode(sha256((v.id::text || p::text)::bytea), 'hex'),
       true, v.created_at, '[]'::jsonb
FROM visit v, generate_series(1, :per) AS p
WHERE v.tenant_id = :tid AND v.notes = 'Scale visit'
"""
        ),
        {**common, "per": PHOTOS_PER_VISIT},
    )

    # -------------------------------------------------------------- diagnoses
    await session.execute(
        text(
            """
INSERT INTO diagnosis (id, tenant_id, created_at, updated_at, version, subject, farmer_id,
                       images, language, status, model_versions, llm_used, flagged, attempts)
SELECT gen_random_uuid(), :tid, f.created_at, CAST(:now AS timestamptz), 1, 'officer', f.id,
       '[]'::jsonb, 'te', 'answered', '{}'::jsonb, false, false, 1
FROM farmer f
WHERE f.tenant_id = :tid AND f.name LIKE 'Scale Farmer %'
  AND abs(hashtext(f.id::text)) % :share = 0
"""
        ),
        {**common, "share": DIAGNOSIS_SHARE},
    )

    # -------------------------------------------------------------- orders
    await session.execute(
        text(
            """
INSERT INTO "order" (id, tenant_id, created_at, updated_at, version, farmer_id, store_id,
                     channel, status, fulfilment, subtotal_paise, discount_paise, tax_paise,
                     total_paise, placed_at, notes)
SELECT gen_random_uuid(), :tid, f.created_at, CAST(:now AS timestamptz), 1, f.id,
       (CAST(:stores AS uuid[]))[
           1 + (abs(hashtext(f.id::text)) % array_length(CAST(:stores AS uuid[]), 1))],
       'officer', 'delivered', 'pickup', 100000, 0, 18000, 118000, f.created_at, 'scale'
FROM farmer f
WHERE f.tenant_id = :tid AND f.name LIKE 'Scale Farmer %'
  AND abs(hashtext(f.id::text)) % :share = 1
"""
        ),
        {**common, "share": ORDER_SHARE},
    )

    # -------------------------------------------------------------- location points
    # ``location_point`` is partitioned by day (migration 0010); the partitions for the window
    # must exist first. This is the table that grows fastest, and partitioning is why it does
    # not need an index change at this volume — see docs/perf/NF-007.md.
    from farmerapp.location import partitions

    await partitions.ensure_partitions(
        session,
        from_day=(moment - timedelta(days=LOCATION_DAYS + 1)).date(),
        to_day=(moment + timedelta(days=1)).date(),
    )
    await session.execute(
        text(
            """
INSERT INTO location_point (id, ts, tenant_id, officer_id, point, accuracy_m, is_mock,
                            is_rooted, clock_drift_s, received_at)
SELECT gen_random_uuid(),
       CAST(:now AS timestamptz) - (d * interval '1 day') + (p * interval '2 minutes'),
       :tid,
       o.officer,
       ST_SetSRID(ST_MakePoint(:lon + (random() - 0.5) * 0.2,
                               :lat + (random() - 0.5) * 0.2), 4326)::geography,
       8.0, false, false, 0, CAST(:now AS timestamptz)
FROM unnest(CAST(:officers AS uuid[])) AS o(officer),
     generate_series(1, :days) AS d,
     generate_series(1, :per_day) AS p
"""
        ),
        {
            **common,
            "lat": BASE_LAT,
            "lon": BASE_LON,
            "days": LOCATION_DAYS,
            "per_day": POINTS_PER_OFFICER_DAY,
        },
    )

    await session.commit()
    # The binding is transaction-local (``set_config(..., is_local => true)``), so the commit
    # dropped it: bind again before counting, or RLS answers zero for everything.
    from farmerapp.db.session import set_tenant

    await set_tenant(session, tenant_id)
    _ = marker
    return ScaleData(
        tenant_id=tenant_id,
        officers=officers,
        farmers=await _count(session, "farmer", tenant_id),
        visits=await _count(session, "visit", tenant_id),
        photos=await _count(session, "visit_photo", tenant_id),
        diagnoses=await _count(session, "diagnosis", tenant_id),
        orders=await _count(session, "order", tenant_id),
        location_points=await _count(session, "location_point", tenant_id),
        seconds=(datetime.now(UTC) - started).total_seconds(),
    )


__all__ = [
    "FARMERS",
    "LOCATION_DAYS",
    "OFFICERS",
    "PHOTOS_PER_VISIT",
    "POINTS_PER_OFFICER_DAY",
    "ScaleData",
    "build",
]
