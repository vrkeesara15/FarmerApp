"""M1: cluster, store, village, crop, farmer, farm, crop_plot, consent_record

Revision ID: 0005
Revises: 0004
Create Date: 2026-09-18 00:00:00 UTC

M1-KICKOFF (SPEC 8.2 entities for FA-012 / FA-013 / FM-002 / FA-014). Backward compatible:
eight new tables, nothing existing is touched (``user.store_id`` / ``user.cluster_id`` stay
plain uuids; they will get foreign keys in a later expand step once every environment has
the tables).

* ``cluster``, ``store`` (``geography(Point)`` location, optional polygon geofence, GiST),
  ``village`` (``store_id`` — the store that serves it, location, optional meeting point).
* ``crop`` master (code unique per tenant, ``names`` jsonb per language).
* ``farmer`` unique ``(tenant_id, phone)``, ``phone_last4``, ``village_id``, ``registered_by``
  / ``user_id`` -> ``user``, ``source``, ``land_ownership``, consent cache; pg_trgm index on
  ``name`` (VA-F02).
* ``farm`` with ``boundary geography(Polygon, 4326)`` and two **stored generated columns**
  ``centroid`` (``ST_Centroid``) and ``area_acres_computed`` (``ST_Area`` / 4046.8564224),
  both GiST/B-tree indexable for VA-F02 / VA-F03.
* ``crop_plot`` -> ``farm`` + ``crop``.
* ``consent_record``: lean ``TenantRow`` columns, **append-only** for the app role
  (``enable_rls(..., append_only=True)``; listed in ``APPEND_ONLY_TABLES``).

Every table: ``enable_rls`` (tenant isolation, forced), FK indexes.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geography
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

ACRE_M2 = "4046.8564224"
IRRIGATION = ("rainfed", "borewell", "canal", "tank", "open_well", "drip", "sprinkler")
STAGES = ("sown", "vegetative", "flowering", "fruiting", "maturity", "harvested")
TABLES = ("cluster", "store", "village", "crop", "farmer", "farm", "crop_plot", "consent_record")


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


def _point(nullable: bool) -> sa.Column[Any]:
    return sa.Column(
        "location",
        Geography(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=nullable,
    )


def _polygon(name: str, nullable: bool = True) -> sa.Column[Any]:
    return sa.Column(
        name, Geography(geometry_type="POLYGON", srid=4326, spatial_index=False), nullable=nullable
    )


def _state() -> sa.Column[Any]:
    return sa.Column(
        "state", sa.String(length=80), server_default=sa.text("'Telangana'"), nullable=False
    )


def _quoted(values: Sequence[str]) -> str:
    return ", ".join(f"'{v}'" for v in values)


def _tenant_index(table: str) -> None:
    op.create_index(op.f(f"ix_{table}_tenant_id"), table, ["tenant_id"], unique=False)


def upgrade() -> None:
    # ------------------------------------------------------------------ geography
    op.create_table(
        "cluster",
        *_base_columns(),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("district", sa.String(length=80), nullable=True),
        _state(),
        _point(nullable=True),
        _polygon("geofence"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_cluster")),
        sa.UniqueConstraint("tenant_id", "name", name=op.f("uq_cluster_tenant_id")),
    )
    _tenant_index("cluster")
    enable_rls("cluster")

    op.create_table(
        "store",
        *_base_columns(),
        sa.Column("code", sa.String(length=16), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("cluster_id", sa.Uuid(), nullable=True),
        sa.Column("district", sa.String(length=80), nullable=False),
        _state(),
        _point(nullable=False),
        _polygon("geofence"),
        sa.ForeignKeyConstraint(
            ["cluster_id"],
            ["cluster.id"],
            name=op.f("fk_store_cluster_id_cluster"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_store")),
        sa.UniqueConstraint("tenant_id", "code", name=op.f("uq_store_tenant_id")),
    )
    _tenant_index("store")
    op.create_index("ix_store_cluster_id", "store", ["cluster_id"], unique=False)
    op.create_index(
        "ix_store_location", "store", ["location"], unique=False, postgresql_using="gist"
    )
    enable_rls("store")

    op.create_table(
        "village",
        *_base_columns(),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("district", sa.String(length=80), nullable=False),
        sa.Column("mandal", sa.String(length=80), nullable=False),
        _state(),
        sa.Column("store_id", sa.Uuid(), nullable=True),
        _point(nullable=False),
        sa.Column(
            "meeting_point",
            Geography(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(
            ["store_id"], ["store.id"], name=op.f("fk_village_store_id_store"), ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_village")),
        sa.UniqueConstraint(
            "tenant_id", "district", "mandal", "name", name=op.f("uq_village_tenant_id")
        ),
    )
    _tenant_index("village")
    op.create_index("ix_village_store_id", "village", ["store_id"], unique=False)
    op.create_index(
        "ix_village_location", "village", ["location"], unique=False, postgresql_using="gist"
    )
    enable_rls("village")

    # ------------------------------------------------------------------ master data
    op.create_table(
        "crop",
        *_base_columns(),
        sa.Column("code", sa.String(length=32), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column(
            "names",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column("duration_days", sa.Integer(), nullable=True),
        sa.Column("active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_crop")),
        sa.UniqueConstraint("tenant_id", "code", name=op.f("uq_crop_tenant_id")),
    )
    _tenant_index("crop")
    enable_rls("crop")

    # ------------------------------------------------------------------ farmers
    op.create_table(
        "farmer",
        *_base_columns(),
        sa.Column("phone", sa.String(length=16), nullable=False),
        sa.Column("phone_last4", sa.String(length=4), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("village_id", sa.Uuid(), nullable=False),
        sa.Column("landmark", sa.String(length=200), nullable=True),
        sa.Column("language", sa.String(length=8), server_default=sa.text("'te'"), nullable=False),
        sa.Column(
            "consent_marketing", sa.Boolean(), server_default=sa.text("false"), nullable=False
        ),
        sa.Column("consent_version", sa.String(length=32), nullable=True),
        sa.Column("registered_by", sa.Uuid(), nullable=True),
        sa.Column("user_id", sa.Uuid(), nullable=True),
        sa.Column(
            "source", sa.String(length=16), server_default=sa.text("'officer'"), nullable=False
        ),
        sa.Column("land_ownership", sa.String(length=16), nullable=True),
        sa.CheckConstraint(
            f"source IN ({_quoted(('officer', 'app', 'import'))})", name=op.f("ck_farmer_source")
        ),
        sa.CheckConstraint(
            "land_ownership IS NULL OR land_ownership IN ('own', 'leased')",
            name=op.f("ck_farmer_land_ownership"),
        ),
        sa.CheckConstraint("char_length(phone_last4) = 4", name=op.f("ck_farmer_phone_last4")),
        sa.ForeignKeyConstraint(
            ["village_id"],
            ["village.id"],
            name=op.f("fk_farmer_village_id_village"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["registered_by"],
            ["user.id"],
            name=op.f("fk_farmer_registered_by_user"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user.id"], name=op.f("fk_farmer_user_id_user"), ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_farmer")),
        sa.UniqueConstraint("tenant_id", "phone", name=op.f("uq_farmer_tenant_id")),
    )
    _tenant_index("farmer")
    op.create_index("ix_farmer_village_id", "farmer", ["village_id"], unique=False)
    op.create_index("ix_farmer_registered_by", "farmer", ["registered_by"], unique=False)
    op.create_index("ix_farmer_user_id", "farmer", ["user_id"], unique=False)
    op.create_index(
        "ix_farmer_tenant_phone_last4", "farmer", ["tenant_id", "phone_last4"], unique=False
    )
    op.create_index(
        "ix_farmer_name_trgm",
        "farmer",
        ["name"],
        unique=False,
        postgresql_using="gin",
        postgresql_ops={"name": "gin_trgm_ops"},
    )
    enable_rls("farmer")

    op.create_table(
        "farm",
        *_base_columns(),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=True),
        sa.Column("survey_no", sa.String(length=64), nullable=True),
        _polygon("boundary"),
        sa.Column("area_acres", sa.Numeric(precision=8, scale=2), nullable=False),
        sa.Column("soil", sa.String(length=16), nullable=True),
        sa.Column("irrigation", sa.String(length=16), nullable=True),
        sa.Column("ownership", sa.String(length=16), nullable=True),
        sa.Column(
            "centroid",
            Geography(geometry_type="POINT", srid=4326, spatial_index=False),
            sa.Computed("ST_Centroid(boundary)", persisted=True),
            nullable=True,
        ),
        sa.Column(
            "area_acres_computed",
            sa.Numeric(precision=10, scale=3),
            sa.Computed(f"(ST_Area(boundary) / {ACRE_M2})::numeric(10, 3)", persisted=True),
            nullable=True,
        ),
        sa.CheckConstraint(
            "soil IS NULL OR soil IN "
            f"({_quoted(('black', 'red', 'sandy', 'loamy', 'clay', 'alluvial', 'laterite'))})",
            name=op.f("ck_farm_soil"),
        ),
        sa.CheckConstraint(
            f"irrigation IS NULL OR irrigation IN ({_quoted(IRRIGATION)})",
            name=op.f("ck_farm_irrigation"),
        ),
        sa.CheckConstraint(
            "ownership IS NULL OR ownership IN ('own', 'leased')", name=op.f("ck_farm_ownership")
        ),
        sa.CheckConstraint("area_acres > 0", name=op.f("ck_farm_area_acres")),
        sa.ForeignKeyConstraint(
            ["farmer_id"], ["farmer.id"], name=op.f("fk_farm_farmer_id_farmer"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_farm")),
    )
    _tenant_index("farm")
    op.create_index("ix_farm_farmer_id", "farm", ["farmer_id"], unique=False)
    op.create_index("ix_farm_boundary", "farm", ["boundary"], unique=False, postgresql_using="gist")
    op.create_index("ix_farm_centroid", "farm", ["centroid"], unique=False, postgresql_using="gist")
    enable_rls("farm")

    op.create_table(
        "crop_plot",
        *_base_columns(),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=False),
        sa.Column("variety", sa.String(length=80), nullable=True),
        sa.Column("season", sa.String(length=8), nullable=False),
        sa.Column("sowing_date", sa.Date(), nullable=False),
        sa.Column("stage", sa.String(length=16), nullable=True),
        sa.Column("expected_harvest", sa.Date(), nullable=True),
        sa.Column("area_acres", sa.Numeric(precision=8, scale=2), nullable=True),
        sa.CheckConstraint(
            "season IN ('kharif', 'rabi', 'zaid')", name=op.f("ck_crop_plot_season")
        ),
        sa.CheckConstraint(
            f"stage IS NULL OR stage IN ({_quoted(STAGES)})",
            name=op.f("ck_crop_plot_stage"),
        ),
        sa.CheckConstraint(
            "area_acres IS NULL OR area_acres > 0", name=op.f("ck_crop_plot_area_acres")
        ),
        sa.ForeignKeyConstraint(
            ["farm_id"], ["farm.id"], name=op.f("fk_crop_plot_farm_id_farm"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["crop_id"], ["crop.id"], name=op.f("fk_crop_plot_crop_id_crop"), ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_crop_plot")),
    )
    _tenant_index("crop_plot")
    op.create_index("ix_crop_plot_farm_id", "crop_plot", ["farm_id"], unique=False)
    op.create_index("ix_crop_plot_crop_id", "crop_plot", ["crop_id"], unique=False)
    enable_rls("crop_plot")

    # ------------------------------------------------------------------ consent (append-only)
    op.create_table(
        "consent_record",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("subject_type", sa.String(length=16), nullable=False),
        sa.Column("subject_id", sa.Uuid(), nullable=False),
        sa.Column("purpose", sa.String(length=32), nullable=False),
        sa.Column("version", sa.String(length=32), nullable=False),
        sa.Column("language", sa.String(length=8), nullable=True),
        sa.Column("granted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("withdrawn_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("channel", sa.String(length=16), nullable=False),
        sa.Column("recorded_by", sa.Uuid(), nullable=True),
        sa.CheckConstraint(
            "subject_type IN ('farmer', 'user')", name=op.f("ck_consent_record_subject_type")
        ),
        sa.CheckConstraint(
            "purpose IN ('data', 'marketing')", name=op.f("ck_consent_record_purpose")
        ),
        sa.CheckConstraint(
            f"channel IN ({_quoted(('officer', 'app', 'sms', 'whatsapp', 'ivr', 'paper'))})",
            name=op.f("ck_consent_record_channel"),
        ),
        sa.CheckConstraint(
            "(granted_at IS NULL) <> (withdrawn_at IS NULL)",
            name=op.f("ck_consent_record_one_event"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_consent_record")),
    )
    op.create_index(
        "ix_consent_record_subject_purpose_created",
        "consent_record",
        ["tenant_id", "subject_id", "purpose", sa.text("created_at DESC")],
        unique=False,
    )
    enable_rls("consent_record", append_only=True)


def downgrade() -> None:
    for table in reversed(TABLES):
        disable_rls(table)
        op.drop_table(table)
