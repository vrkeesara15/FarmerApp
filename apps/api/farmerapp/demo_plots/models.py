"""FA-026 demo plots.

* ``demo_plot`` — a demonstration on one of a farmer's crop plots: the product / treatment
  used, and what it is compared with (``baseline``): the farmer's usual practice on the same
  field (``farmer_practice``) or another crop plot (``comparison_plot`` +
  ``comparison_crop_plot_id``). Lifecycle ``created -> active -> harvested -> reported``:
  activated when the treatment is applied, ``harvested`` with the yield entry (demo vs
  practice, kg per acre), ``reported`` once shared with the farmer / store. ``last_observed_at``
  feeds the FA-018 "demo plot stage due" beat reason.
* ``demo_observation`` — a stage visit: crop stage, which side (demo / practice / both), a note
  and the stage photos (blob URIs of completed ``demo_plot`` uploads).

Both audited and sync entities (created offline, photos uploaded first).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Numeric, String, Text, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class DemoStatus(StrEnum):
    CREATED = "created"
    ACTIVE = "active"
    HARVESTED = "harvested"
    REPORTED = "reported"


class DemoBaseline(StrEnum):
    FARMER_PRACTICE = "farmer_practice"
    COMPARISON_PLOT = "comparison_plot"


class DemoStage(StrEnum):
    SOWN = "sown"
    VEGETATIVE = "vegetative"
    FLOWERING = "flowering"
    FRUITING = "fruiting"
    MATURITY = "maturity"
    HARVEST = "harvest"


class ObservationSide(StrEnum):
    DEMO = "demo"
    PRACTICE = "practice"
    BOTH = "both"


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


class DemoPlot(Base, BaseColumns):
    __tablename__ = "demo_plot"
    __table_args__ = (
        CheckConstraint(f"status IN ({_in(DemoStatus)})", name="status"),
        CheckConstraint(f"baseline IN ({_in(DemoBaseline)})", name="baseline"),
        CheckConstraint(
            "(baseline = 'comparison_plot') = (comparison_crop_plot_id IS NOT NULL)",
            name="comparison",
        ),
        CheckConstraint(
            "demo_yield_kg_per_acre IS NULL OR demo_yield_kg_per_acre >= 0", name="demo_yield"
        ),
        CheckConstraint(
            "practice_yield_kg_per_acre IS NULL OR practice_yield_kg_per_acre >= 0",
            name="practice_yield",
        ),
        CheckConstraint(
            "status NOT IN ('harvested', 'reported') OR demo_yield_kg_per_acre IS NOT NULL",
            name="yield_when_harvested",
        ),
        Index("ix_demo_plot_officer", "tenant_id", "officer_id", "status"),
        Index("ix_demo_plot_farmer_id", "farmer_id"),
    )

    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="RESTRICT"), nullable=False
    )
    farm_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farm.id", ondelete="RESTRICT"), nullable=False
    )
    crop_plot_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop_plot.id", ondelete="RESTRICT"), nullable=False
    )
    baseline: Mapped[str] = mapped_column(String(16), nullable=False)
    comparison_crop_plot_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("crop_plot.id", ondelete="RESTRICT"), nullable=True
    )
    product_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("product.id", ondelete="SET NULL"), nullable=True
    )
    treatment: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(
        String(12),
        nullable=False,
        default=DemoStatus.CREATED.value,
        server_default=text("'created'"),
    )
    stage: Mapped[str | None] = mapped_column(String(16), nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    harvested_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    reported_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_observed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    demo_yield_kg_per_acre: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    practice_yield_kg_per_acre: Mapped[Decimal | None] = mapped_column(
        Numeric(10, 2), nullable=True
    )
    yield_note: Mapped[str | None] = mapped_column(Text, nullable=True)


class DemoObservation(Base, BaseColumns):
    __tablename__ = "demo_observation"
    __table_args__ = (
        CheckConstraint(f"stage IN ({_in(DemoStage)})", name="stage"),
        CheckConstraint(f"side IN ({_in(ObservationSide)})", name="side"),
        Index("ix_demo_observation_plot", "demo_plot_id", "observed_at"),
    )

    demo_plot_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("demo_plot.id", ondelete="CASCADE"), nullable=False
    )
    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    stage: Mapped[str] = mapped_column(String(16), nullable=False)
    side: Mapped[str] = mapped_column(
        String(8), nullable=False, default=ObservationSide.DEMO.value, server_default=text("'demo'")
    )
    observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    photo_uris: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, default=list, server_default=text("'[]'::jsonb")
    )
    data: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict, server_default=text("'{}'::jsonb")
    )


__all__ = [
    "DemoBaseline",
    "DemoObservation",
    "DemoPlot",
    "DemoStage",
    "DemoStatus",
    "ObservationSide",
]
