"""M2: duty_session, location_point (partitioned by day), location_daily_agg,
policy_acceptance, visit, visit_photo, visit_confirmation, village.meeting_point_radius_m

Revision ID: 0007
Revises: 0006
Create Date: 2026-09-18 18:00:00 UTC

M2-KICKOFF (SPEC 8.2 entities for FA-010 / FA-011 / FA-014 .. FA-017 / FA-028 / VV-001 ..
VV-010). Backward compatible: seven new tables, two SQL functions and one nullable column;
nothing existing is touched otherwise.

* ``village.meeting_point_radius_m integer NULL`` (VV-003; NULL -> tenant ``geofence_radius_m``).
* ``duty_session`` (officer, start / end, points, km, stops jsonb, end_reason, policy_version,
  device, app version).
* ``location_point`` — ``PARTITION BY RANGE (ts)``, primary key ``(id, ts)``, indexes on
  ``(tenant_id, officer_id, ts)`` and ``(duty_session_id, ts)`` (inherited by every
  partition), RLS enabled + forced on the parent. No DEFAULT partition.
  ``ensure_location_partitions(from_day date, to_day date)`` and
  ``ensure_location_partitions(days_ahead integer)`` — SECURITY DEFINER (owned by the
  migrating role, which owns the parent) — create the missing daily partitions
  ``location_point_pYYYYMMDD`` (UTC days) with RLS enabled + forced, the ``tenant_isolation``
  and ``maintenance`` policies and DML for the app role, and return the names created.
  The migration creates yesterday .. today + 7.
  ``purge_location_points(retention_days integer, dry_run boolean)`` — SECURITY DEFINER —
  lists the partitions older than the window (refuses < 180 days, SPEC 2.6) and, unless
  ``dry_run``, upserts per officer / day rows into ``location_daily_agg`` then drops them.
  The app role may EXECUTE the three functions (the jobs run as the app role); it still has
  no DDL of its own.
* ``location_daily_agg`` (officer, day, km, points, first_ts, last_ts) unique per officer/day.
* ``policy_acceptance`` (user, policy_key, version, accepted_at, device, app version,
  text_hash) **append-only** for the app role.
* ``visit`` (officer, farmer, farm, village, purpose, check-in / check-out time and point,
  accuracy, geofence_result, override note / approver, notes, crop_stage, **generated**
  ``duration_s``, score, score_components jsonb, status, confirmation_channel, confirmed_at,
  device_integrity jsonb, client_visit_id unique per tenant) with a GiST index on the
  check-in point (VA-E03).
* ``visit_photo`` (visit, blob_uri, sha256, phash, exif_time, exif_point, taken_in_app,
  device_time, server_time) with ``(tenant_id, phash)`` / ``(tenant_id, sha256)`` indexes
  (VA-E08).
* ``visit_confirmation`` (visit, channel, otp_challenge, farmer_phone_last4, confirmed_at,
  confirmed_via_device_id, rating, rating_reason) with VA-E05 indexes.

Every table: ``enable_rls`` (tenant isolation, forced), FK indexes.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geography
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import APP_ROLE, MIGRATE_ROLE, disable_rls, enable_rls

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TABLES = (
    "duty_session",
    "location_point",
    "location_daily_agg",
    "policy_acceptance",
    "visit",
    "visit_photo",
    "visit_confirmation",
)
END_REASONS = ("manual", "auto_time", "auto_idle", "forced")
PROVIDERS = ("fused", "gps", "network")
PURPOSES = ("advisory", "scouting", "demo", "collection", "sale", "meeting")
GEOFENCE_RESULTS = ("inside", "outside", "meeting_point", "override")
STATUSES = ("verified", "partial", "unverified", "open")
CHANNELS = ("sms_otp", "app_push", "qr", "none")
STAGES = ("sown", "vegetative", "flowering", "fruiting", "maturity", "harvested")
PARTITION_PREFIX = "location_point_p"
RETENTION_DAYS = 180

# --------------------------------------------------------------------------- SQL functions
# Plain strings (no f-strings around the $$ bodies); the only substitutions are role names.
ENSURE_PARTITIONS_RANGE = f"""
CREATE OR REPLACE FUNCTION public.ensure_location_partitions(from_day date, to_day date)
RETURNS SETOF text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    d date;
    name text;
BEGIN
    IF from_day IS NULL OR to_day IS NULL OR to_day < from_day THEN
        RAISE EXCEPTION 'ensure_location_partitions: to_day must not precede from_day';
    END IF;
    IF to_day - from_day > 400 THEN
        RAISE EXCEPTION 'ensure_location_partitions: at most 400 days per call';
    END IF;
    d := from_day;
    WHILE d <= to_day LOOP
        name := '{PARTITION_PREFIX}' || to_char(d, 'YYYYMMDD');
        IF to_regclass('public.' || name) IS NULL THEN
            EXECUTE format(
                'CREATE TABLE public.%I PARTITION OF public.location_point '
                'FOR VALUES FROM (%L) TO (%L)',
                name, (d::timestamp AT TIME ZONE 'UTC'), ((d + 1)::timestamp AT TIME ZONE 'UTC')
            );
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', name);
            EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', name);
            EXECUTE format(
                'CREATE POLICY tenant_isolation ON public.%I AS PERMISSIVE FOR ALL TO PUBLIC '
                'USING (tenant_id = app_current_tenant()) '
                'WITH CHECK (tenant_id = app_current_tenant())',
                name
            );
            EXECUTE format(
                'CREATE POLICY maintenance ON public.%I AS PERMISSIVE FOR ALL TO {MIGRATE_ROLE} '
                'USING (true) WITH CHECK (true)',
                name
            );
            EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO {APP_ROLE}', name);
            RETURN NEXT name;
        END IF;
        d := d + 1;
    END LOOP;
    RETURN;
END
$$
""".strip()

ENSURE_PARTITIONS_AHEAD = """
CREATE OR REPLACE FUNCTION public.ensure_location_partitions(days_ahead integer DEFAULT 7)
RETURNS SETOF text
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT public.ensure_location_partitions(current_date - 1, current_date + days_ahead)
$$
""".strip()

PURGE_LOCATION_POINTS = f"""
CREATE OR REPLACE FUNCTION public.purge_location_points(
    retention_days integer DEFAULT {RETENTION_DAYS}, dry_run boolean DEFAULT true
)
RETURNS TABLE (partition_name text, day date, points bigint, officer_days integer, dropped boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    cutoff date;
    r record;
    n bigint;
    agg integer;
BEGIN
    IF retention_days IS NULL OR retention_days < {RETENTION_DAYS} THEN
        RAISE EXCEPTION 'purge_location_points: retention_days must be >= {RETENTION_DAYS}';
    END IF;
    cutoff := current_date - retention_days;
    FOR r IN
        SELECT c.relname AS name,
               to_date(substr(c.relname, length('{PARTITION_PREFIX}') + 1), 'YYYYMMDD') AS d
        FROM pg_inherits i
        JOIN pg_class c ON c.oid = i.inhrelid
        WHERE i.inhparent = 'public.location_point'::regclass
          AND c.relname LIKE '{PARTITION_PREFIX}%'
        ORDER BY c.relname
    LOOP
        CONTINUE WHEN r.d >= cutoff;
        EXECUTE format('SELECT count(*) FROM ONLY public.%I', r.name) INTO n;
        agg := 0;
        dropped := false;
        IF NOT dry_run THEN
            EXECUTE format(
                'INSERT INTO public.location_daily_agg '
                '(id, tenant_id, officer_id, day, km, points, first_ts, last_ts, '
                ' created_at, updated_at) '
                'SELECT gen_random_uuid(), tenant_id, officer_id, %L::date, '
                '       round((sum(step) / 1000.0)::numeric, 2), count(*), '
                '       min(ts), max(ts), now(), now() '
                'FROM (SELECT tenant_id, officer_id, ts, '
                '             coalesce(ST_Distance(point, lag(point) OVER '
                '                 (PARTITION BY tenant_id, officer_id ORDER BY ts)), 0) AS step '
                '      FROM ONLY public.%I) s '
                'GROUP BY tenant_id, officer_id '
                'ON CONFLICT (tenant_id, officer_id, day) DO UPDATE SET km = EXCLUDED.km, '
                '  points = EXCLUDED.points, first_ts = EXCLUDED.first_ts, '
                '  last_ts = EXCLUDED.last_ts, '
                '  updated_at = now()',
                r.d, r.name
            );
            GET DIAGNOSTICS agg = ROW_COUNT;
            EXECUTE format('DROP TABLE public.%I', r.name);
            dropped := true;
        END IF;
        partition_name := r.name;
        day := r.d;
        points := n;
        officer_days := agg;
        RETURN NEXT;
    END LOOP;
    RETURN;
END
$$
""".strip()

FUNCTION_SIGNATURES = (
    "public.ensure_location_partitions(date, date)",
    "public.ensure_location_partitions(integer)",
    "public.purge_location_points(integer, boolean)",
)


def _base_columns() -> list[sa.Column[Any]]:
    return [
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
    ]


def _lean_columns() -> list[sa.Column[Any]]:
    return [
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def _point(name: str, nullable: bool = True) -> sa.Column[Any]:
    return sa.Column(
        name, Geography(geometry_type="POINT", srid=4326, spatial_index=False), nullable=nullable
    )


def _jsonb(name: str, default: str, nullable: bool = False) -> sa.Column[Any]:
    return sa.Column(
        name,
        postgresql.JSONB(astext_type=sa.Text()),
        server_default=sa.text(f"'{default}'::jsonb"),
        nullable=nullable,
    )


def _quoted(values: Sequence[str]) -> str:
    return ", ".join(f"'{v}'" for v in values)


def _tenant_index(table: str) -> None:
    op.create_index(op.f(f"ix_{table}_tenant_id"), table, ["tenant_id"], unique=False)


def upgrade() -> None:
    # ------------------------------------------------------------------ village radius
    op.add_column("village", sa.Column("meeting_point_radius_m", sa.Integer(), nullable=True))
    op.create_check_constraint(
        op.f("ck_village_meeting_point_radius_m"),
        "village",
        "meeting_point_radius_m IS NULL OR meeting_point_radius_m > 0",
    )

    # ------------------------------------------------------------------ duty_session
    op.create_table(
        "duty_session",
        *_base_columns(),
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_at", sa.DateTime(timezone=True), nullable=True),
        _point("start_point"),
        _point("end_point"),
        sa.Column("km", sa.Numeric(precision=8, scale=2), nullable=True),
        _jsonb("stops", "[]"),
        sa.Column("end_reason", sa.String(length=16), nullable=True),
        sa.Column("policy_version", sa.String(length=32), nullable=False),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.CheckConstraint(
            f"end_reason IS NULL OR end_reason IN ({_quoted(END_REASONS)})",
            name=op.f("ck_duty_session_end_reason"),
        ),
        sa.CheckConstraint(
            "end_at IS NULL OR end_at >= start_at", name=op.f("ck_duty_session_end_after_start")
        ),
        sa.CheckConstraint(
            "(end_at IS NULL) = (end_reason IS NULL)",
            name=op.f("ck_duty_session_end_reason_with_end"),
        ),
        sa.CheckConstraint("km IS NULL OR km >= 0", name=op.f("ck_duty_session_km")),
        sa.ForeignKeyConstraint(
            ["officer_id"],
            ["user.id"],
            name=op.f("fk_duty_session_officer_id_user"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_duty_session")),
    )
    _tenant_index("duty_session")
    op.create_index(
        "ix_duty_session_tenant_officer_start",
        "duty_session",
        ["tenant_id", "officer_id", "start_at"],
        unique=False,
    )
    enable_rls("duty_session")

    # ------------------------------------------------------------------ location_point
    op.create_table(
        "location_point",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("ts", sa.DateTime(timezone=True), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("duty_session_id", sa.Uuid(), nullable=True),
        _point("point", nullable=False),
        sa.Column("accuracy_m", sa.Float(), nullable=False),
        sa.Column("speed_mps", sa.Float(), nullable=True),
        sa.Column("bearing", sa.Float(), nullable=True),
        sa.Column("battery_pct", sa.SmallInteger(), nullable=True),
        sa.Column("is_mock", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_rooted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("clock_drift_s", sa.Integer(), server_default="0", nullable=False),
        sa.Column("provider", sa.String(length=16), nullable=True),
        sa.Column(
            "received_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            f"provider IS NULL OR provider IN ({_quoted(PROVIDERS)})",
            name=op.f("ck_location_point_provider"),
        ),
        sa.CheckConstraint(
            "battery_pct IS NULL OR battery_pct BETWEEN 0 AND 100",
            name=op.f("ck_location_point_battery_pct"),
        ),
        sa.CheckConstraint("accuracy_m >= 0", name=op.f("ck_location_point_accuracy_m")),
        sa.PrimaryKeyConstraint("id", "ts", name=op.f("pk_location_point")),
        postgresql_partition_by="RANGE (ts)",
    )
    op.create_index(
        "ix_location_point_tenant_officer_ts",
        "location_point",
        ["tenant_id", "officer_id", "ts"],
        unique=False,
    )
    op.create_index(
        "ix_location_point_duty_session_ts",
        "location_point",
        ["duty_session_id", "ts"],
        unique=False,
    )
    enable_rls("location_point")
    for statement in (ENSURE_PARTITIONS_RANGE, ENSURE_PARTITIONS_AHEAD, PURGE_LOCATION_POINTS):
        op.execute(statement)
    for signature in FUNCTION_SIGNATURES:
        op.execute(f"REVOKE ALL ON FUNCTION {signature} FROM PUBLIC")
        op.execute(f"GRANT EXECUTE ON FUNCTION {signature} TO {APP_ROLE}, {MIGRATE_ROLE}")

    # ------------------------------------------------------------------ location_daily_agg
    op.create_table(
        "location_daily_agg",
        *_lean_columns(),
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("km", sa.Numeric(precision=8, scale=2), nullable=False),
        sa.Column("points", sa.Integer(), nullable=False),
        sa.Column("first_ts", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_ts", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "km >= 0 AND points >= 0", name=op.f("ck_location_daily_agg_non_negative")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_location_daily_agg")),
        sa.UniqueConstraint(
            "tenant_id", "officer_id", "day", name=op.f("uq_location_daily_agg_tenant_id")
        ),
    )
    enable_rls("location_daily_agg")

    # ------------------------------------------------------------------ policy_acceptance
    op.create_table(
        "policy_acceptance",
        *_lean_columns(),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "policy_key",
            sa.String(length=32),
            server_default=sa.text("'location_policy'"),
            nullable=False,
        ),
        sa.Column("version", sa.String(length=32), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.Column("text_hash", sa.String(length=64), nullable=True),
        sa.CheckConstraint(
            "char_length(policy_key) > 0 AND char_length(version) > 0",
            name=op.f("ck_policy_acceptance_keys"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["user.id"],
            name=op.f("fk_policy_acceptance_user_id_user"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_policy_acceptance")),
    )
    op.create_index(
        "ix_policy_acceptance_user_key_accepted",
        "policy_acceptance",
        ["tenant_id", "user_id", "policy_key", sa.text("accepted_at DESC")],
        unique=False,
    )
    enable_rls("policy_acceptance", append_only=True)

    # ------------------------------------------------------------------ visit
    op.create_table(
        "visit",
        *_base_columns(),
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=True),
        sa.Column("village_id", sa.Uuid(), nullable=True),
        sa.Column("purpose", sa.String(length=16), nullable=False),
        sa.Column("checkin_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("checkout_at", sa.DateTime(timezone=True), nullable=True),
        _point("checkin_point", nullable=False),
        sa.Column("checkin_accuracy_m", sa.Float(), nullable=True),
        _point("checkout_point"),
        sa.Column("geofence_result", sa.String(length=16), nullable=False),
        sa.Column("override_note", sa.Text(), nullable=True),
        sa.Column("override_approved_by", sa.Uuid(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("crop_stage", sa.String(length=16), nullable=True),
        sa.Column(
            "duration_s",
            sa.Integer(),
            sa.Computed(
                "(EXTRACT(EPOCH FROM (checkout_at - checkin_at)))::integer", persisted=True
            ),
            nullable=True,
        ),
        sa.Column("score", sa.Integer(), nullable=True),
        sa.Column("score_components", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("status", sa.String(length=16), server_default=sa.text("'open'"), nullable=False),
        sa.Column(
            "confirmation_channel",
            sa.String(length=16),
            server_default=sa.text("'none'"),
            nullable=False,
        ),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        _jsonb("device_integrity", "{}"),
        sa.Column("client_visit_id", sa.Uuid(), nullable=True),
        sa.CheckConstraint(f"purpose IN ({_quoted(PURPOSES)})", name=op.f("ck_visit_purpose")),
        sa.CheckConstraint(
            f"geofence_result IN ({_quoted(GEOFENCE_RESULTS)})",
            name=op.f("ck_visit_geofence_result"),
        ),
        sa.CheckConstraint(f"status IN ({_quoted(STATUSES)})", name=op.f("ck_visit_status")),
        sa.CheckConstraint(
            f"confirmation_channel IN ({_quoted(CHANNELS)})",
            name=op.f("ck_visit_confirmation_channel"),
        ),
        sa.CheckConstraint(
            f"crop_stage IS NULL OR crop_stage IN ({_quoted(STAGES)})",
            name=op.f("ck_visit_crop_stage"),
        ),
        sa.CheckConstraint(
            "checkout_at IS NULL OR checkout_at >= checkin_at", name=op.f("ck_visit_checkout")
        ),
        sa.CheckConstraint("score IS NULL OR score BETWEEN 0 AND 100", name=op.f("ck_visit_score")),
        sa.CheckConstraint(
            "geofence_result <> 'override' OR override_note IS NOT NULL",
            name=op.f("ck_visit_override_note"),
        ),
        sa.ForeignKeyConstraint(
            ["officer_id"], ["user.id"], name=op.f("fk_visit_officer_id_user"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_visit_farmer_id_farmer"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["farm_id"], ["farm.id"], name=op.f("fk_visit_farm_id_farm"), ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["village_id"],
            ["village.id"],
            name=op.f("fk_visit_village_id_village"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["override_approved_by"],
            ["user.id"],
            name=op.f("fk_visit_override_approved_by_user"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_visit")),
        sa.UniqueConstraint("tenant_id", "client_visit_id", name=op.f("uq_visit_tenant_id")),
    )
    _tenant_index("visit")
    op.create_index(
        "ix_visit_tenant_officer_checkin",
        "visit",
        ["tenant_id", "officer_id", "checkin_at"],
        unique=False,
    )
    op.create_index("ix_visit_farmer_id", "visit", ["farmer_id"], unique=False)
    op.create_index("ix_visit_farm_id", "visit", ["farm_id"], unique=False)
    op.create_index("ix_visit_tenant_status", "visit", ["tenant_id", "status"], unique=False)
    op.create_index(
        "ix_visit_checkin_point", "visit", ["checkin_point"], unique=False, postgresql_using="gist"
    )
    enable_rls("visit")

    # ------------------------------------------------------------------ visit_photo
    op.create_table(
        "visit_photo",
        *_base_columns(),
        sa.Column("visit_id", sa.Uuid(), nullable=False),
        sa.Column("blob_uri", sa.String(length=512), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=True),
        sa.Column("phash", sa.Text(), nullable=True),
        sa.Column("exif_time", sa.DateTime(timezone=True), nullable=True),
        _point("exif_point"),
        sa.Column("taken_in_app", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("device_time", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "server_time",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint("char_length(blob_uri) > 0", name=op.f("ck_visit_photo_blob_uri")),
        sa.ForeignKeyConstraint(
            ["visit_id"],
            ["visit.id"],
            name=op.f("fk_visit_photo_visit_id_visit"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_visit_photo")),
    )
    _tenant_index("visit_photo")
    op.create_index("ix_visit_photo_visit_id", "visit_photo", ["visit_id"], unique=False)
    op.create_index(
        "ix_visit_photo_tenant_phash", "visit_photo", ["tenant_id", "phash"], unique=False
    )
    op.create_index(
        "ix_visit_photo_tenant_sha256", "visit_photo", ["tenant_id", "sha256"], unique=False
    )
    enable_rls("visit_photo")

    # ------------------------------------------------------------------ visit_confirmation
    op.create_table(
        "visit_confirmation",
        *_base_columns(),
        sa.Column("visit_id", sa.Uuid(), nullable=False),
        sa.Column("channel", sa.String(length=16), nullable=False),
        sa.Column("otp_challenge_id", sa.Uuid(), nullable=True),
        sa.Column("farmer_phone_last4", sa.String(length=4), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("confirmed_via_device_id", sa.String(length=128), nullable=True),
        sa.Column("rating", sa.Integer(), nullable=True),
        sa.Column("rating_reason", sa.String(length=200), nullable=True),
        sa.CheckConstraint(
            f"channel IN ({_quoted(CHANNELS)}) AND channel <> 'none'",
            name=op.f("ck_visit_confirmation_channel"),
        ),
        sa.CheckConstraint(
            "rating IS NULL OR rating BETWEEN 1 AND 5", name=op.f("ck_visit_confirmation_rating")
        ),
        sa.CheckConstraint(
            "farmer_phone_last4 IS NULL OR char_length(farmer_phone_last4) = 4",
            name=op.f("ck_visit_confirmation_farmer_phone_last4"),
        ),
        sa.ForeignKeyConstraint(
            ["visit_id"],
            ["visit.id"],
            name=op.f("fk_visit_confirmation_visit_id_visit"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["otp_challenge_id"],
            ["otp_challenge.id"],
            name=op.f("fk_visit_confirmation_otp_challenge_id_otp_challenge"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_visit_confirmation")),
    )
    _tenant_index("visit_confirmation")
    op.create_index(
        "ix_visit_confirmation_visit_id", "visit_confirmation", ["visit_id"], unique=False
    )
    op.create_index(
        "ix_visit_confirmation_tenant_phone",
        "visit_confirmation",
        ["tenant_id", "farmer_phone_last4"],
        unique=False,
    )
    op.create_index(
        "ix_visit_confirmation_tenant_device",
        "visit_confirmation",
        ["tenant_id", "confirmed_via_device_id"],
        unique=False,
    )
    enable_rls("visit_confirmation")

    # ------------------------------------------------------------------ initial partitions
    op.execute("SELECT public.ensure_location_partitions(7)")


def downgrade() -> None:
    for table in reversed(TABLES):
        disable_rls(table)
        op.drop_table(table)  # location_point drops its partitions with it
    for signature in reversed(FUNCTION_SIGNATURES):
        op.execute(f"DROP FUNCTION IF EXISTS {signature}")
    op.drop_constraint(op.f("ck_village_meeting_point_radius_m"), "village", type_="check")
    op.drop_column("village", "meeting_point_radius_m")
