"""FA-026 demo plot payloads."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from farmerapp.demo_plots.models import DemoObservation, DemoPlot

Baseline = Literal["farmer_practice", "comparison_plot"]
Stage = Literal["sown", "vegetative", "flowering", "fruiting", "maturity", "harvest"]
Side = Literal["demo", "practice", "both"]


class DemoPlotCreate(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client id (offline create).")
    farmer_id: uuid.UUID
    crop_plot_id: uuid.UUID = Field(description="The demo field (a crop plot of the farmer).")
    baseline: Baseline = "farmer_practice"
    comparison_crop_plot_id: uuid.UUID | None = Field(
        default=None, description="Required for `comparison_plot`: the plot compared with."
    )
    product_id: uuid.UUID | None = Field(default=None, description="The product demonstrated.")
    treatment: str = Field(min_length=1, max_length=2000, description="What is applied, how.")

    @model_validator(mode="after")
    def _baseline(self) -> DemoPlotCreate:
        if (self.baseline == "comparison_plot") != (self.comparison_crop_plot_id is not None):
            raise ValueError("comparison_crop_plot_id is required exactly for comparison_plot")
        if self.comparison_crop_plot_id is not None and (
            self.comparison_crop_plot_id == self.crop_plot_id
        ):
            raise ValueError("the comparison plot must differ from the demo plot")
        return self


class ObservationIn(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client id (offline create).")
    stage: Stage
    side: Side = "demo"
    observed_at: datetime
    note: str | None = Field(default=None, max_length=2000)
    photo_uris: list[str] = Field(
        default_factory=list, max_length=10, description="Completed `demo_plot` uploads."
    )


class DemoTransitionIn(BaseModel):
    to: Literal["active", "reported"]
    at: datetime | None = None


class YieldIn(BaseModel):
    demo_yield_kg_per_acre: Decimal = Field(ge=0, le=Decimal("100000"), decimal_places=2)
    practice_yield_kg_per_acre: Decimal | None = Field(
        default=None, ge=0, le=Decimal("100000"), decimal_places=2
    )
    harvested_at: datetime | None = None
    note: str | None = Field(default=None, max_length=2000)


class ObservationOut(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    demo_plot_id: uuid.UUID
    officer_id: uuid.UUID
    stage: str
    side: str
    observed_at: datetime
    note: str | None
    photo_uris: list[str]
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: DemoObservation) -> ObservationOut:
        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            demo_plot_id=row.demo_plot_id,
            officer_id=row.officer_id,
            stage=row.stage,
            side=row.side,
            observed_at=row.observed_at,
            note=row.note,
            photo_uris=list(row.photo_uris or []),
            created_at=row.created_at,
            updated_at=row.updated_at,
            deleted_at=row.deleted_at,
            version=row.version,
        )


class DemoPlotOut(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    officer_id: uuid.UUID
    farmer_id: uuid.UUID
    farm_id: uuid.UUID
    crop_plot_id: uuid.UUID
    baseline: str
    comparison_crop_plot_id: uuid.UUID | None
    product_id: uuid.UUID | None
    treatment: str
    status: str = Field(description="created -> active -> harvested -> reported")
    stage: str | None
    started_at: datetime | None
    harvested_at: datetime | None
    reported_at: datetime | None
    last_observed_at: datetime | None
    demo_yield_kg_per_acre: Decimal | None
    practice_yield_kg_per_acre: Decimal | None
    yield_gain_pct: float | None = Field(
        description="(demo - practice) / practice x 100, when both yields are in."
    )
    yield_note: str | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: DemoPlot) -> DemoPlotOut:
        gain: float | None = None
        demo, practice = row.demo_yield_kg_per_acre, row.practice_yield_kg_per_acre
        if demo is not None and practice:
            gain = round(float((demo - practice) / practice * 100), 1)
        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            officer_id=row.officer_id,
            farmer_id=row.farmer_id,
            farm_id=row.farm_id,
            crop_plot_id=row.crop_plot_id,
            baseline=row.baseline,
            comparison_crop_plot_id=row.comparison_crop_plot_id,
            product_id=row.product_id,
            treatment=row.treatment,
            status=row.status,
            stage=row.stage,
            started_at=row.started_at,
            harvested_at=row.harvested_at,
            reported_at=row.reported_at,
            last_observed_at=row.last_observed_at,
            demo_yield_kg_per_acre=demo,
            practice_yield_kg_per_acre=practice,
            yield_gain_pct=gain,
            yield_note=row.yield_note,
            created_at=row.created_at,
            updated_at=row.updated_at,
            deleted_at=row.deleted_at,
            version=row.version,
        )


class DemoPlotDetailOut(DemoPlotOut):
    observations: list[ObservationOut]


class DemoPlotPage(BaseModel):
    items: list[DemoPlotOut]
    next_cursor: str | None = None


__all__ = [
    "DemoPlotCreate",
    "DemoPlotDetailOut",
    "DemoPlotOut",
    "DemoPlotPage",
    "DemoTransitionIn",
    "ObservationIn",
    "ObservationOut",
    "YieldIn",
]
