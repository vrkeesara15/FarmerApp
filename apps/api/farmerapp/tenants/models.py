"""Tenant geography (SPEC 8.2 ``store / cluster``, plus ``village`` for FA-012 / FA-014).

* ``cluster`` — a group of stores under one cluster head (SPEC 2.6 "own cluster").
* ``store`` — a retail store / field base with a location and an optional geofence.
* ``village`` — where farmers live; mapped to the store that serves it (so a store manager's
  "own store" scope over farmers is village -> store) with a location and an optional
  meeting point (FA-014 / VV-003 check-in at a village meeting point) whose radius
  ``meeting_point_radius_m`` falls back to the tenant's ``geofence_radius_m``
  (``farmerapp.tenants.settings``) when NULL.

All three carry the base columns and RLS (migration 0005). Spatial columns are
``geography(..., 4326)``; see ``farmerapp.db.geo``.
"""

from __future__ import annotations

import uuid
from typing import Any

from geoalchemy2 import Geography
from sqlalchemy import CheckConstraint, ForeignKey, Index, Integer, String, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns
from farmerapp.db.geo import SRID

DEFAULT_STATE = "Telangana"


class Cluster(Base, BaseColumns):
    __tablename__ = "cluster"
    __table_args__ = (UniqueConstraint("tenant_id", "name"),)

    name: Mapped[str] = mapped_column(String(120), nullable=False)
    district: Mapped[str | None] = mapped_column(String(80), nullable=True)
    state: Mapped[str] = mapped_column(
        String(80), nullable=False, server_default=text(f"'{DEFAULT_STATE}'")
    )
    location: Mapped[Any] = mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=True
    )
    geofence: Mapped[Any] = mapped_column(
        Geography(geometry_type="POLYGON", srid=SRID, spatial_index=False), nullable=True
    )


class Store(Base, BaseColumns):
    __tablename__ = "store"
    __table_args__ = (
        UniqueConstraint("tenant_id", "code"),
        Index("ix_store_cluster_id", "cluster_id"),
        Index("ix_store_location", "location", postgresql_using="gist"),
    )

    code: Mapped[str] = mapped_column(String(16), nullable=False)  # short id: WGL, KNR...
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    cluster_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("cluster.id", ondelete="SET NULL"), nullable=True
    )
    district: Mapped[str] = mapped_column(String(80), nullable=False)
    state: Mapped[str] = mapped_column(
        String(80), nullable=False, server_default=text(f"'{DEFAULT_STATE}'")
    )
    location: Mapped[Any] = mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=False
    )
    geofence: Mapped[Any] = mapped_column(
        Geography(geometry_type="POLYGON", srid=SRID, spatial_index=False), nullable=True
    )


class Village(Base, BaseColumns):
    __tablename__ = "village"
    __table_args__ = (
        UniqueConstraint("tenant_id", "district", "mandal", "name"),
        Index("ix_village_store_id", "store_id"),
        Index("ix_village_location", "location", postgresql_using="gist"),
        CheckConstraint(
            "meeting_point_radius_m IS NULL OR meeting_point_radius_m > 0",
            name="meeting_point_radius_m",
        ),
    )

    name: Mapped[str] = mapped_column(String(120), nullable=False)
    district: Mapped[str] = mapped_column(String(80), nullable=False)
    mandal: Mapped[str] = mapped_column(String(80), nullable=False)
    state: Mapped[str] = mapped_column(
        String(80), nullable=False, server_default=text(f"'{DEFAULT_STATE}'")
    )
    store_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("store.id", ondelete="SET NULL"), nullable=True
    )
    location: Mapped[Any] = mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=False
    )
    meeting_point: Mapped[Any] = mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=True
    )
    # VV-003: NULL -> tenant setting ``geofence_radius_m`` (default 150 m).
    meeting_point_radius_m: Mapped[int | None] = mapped_column(Integer, nullable=True)


__all__ = ["DEFAULT_STATE", "Cluster", "Store", "Village"]
