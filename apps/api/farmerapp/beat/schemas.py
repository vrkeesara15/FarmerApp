"""FA-018 beat plan payloads."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator

from farmerapp.beat.models import BeatPlan

ReasonCode = Literal["follow_up_due", "pest_alert", "credit_due", "demo_plot_stage"]


class BeatReason(BaseModel):
    code: ReasonCode
    detail: dict[str, Any] = Field(default_factory=dict)


class BeatItemOut(BaseModel):
    id: uuid.UUID
    kind: Literal["farmer", "village"]
    farmer_id: uuid.UUID | None = None
    farmer_name: str | None = None
    village_id: uuid.UUID
    village_name: str | None = None
    reasons: list[BeatReason] = Field(default_factory=list)
    priority: int = Field(description="Higher first when generated; the officer's order wins.")
    source: Literal["system", "officer"]
    note: str | None = None


class BeatVillageOut(BaseModel):
    village_id: uuid.UUID
    village_name: str | None
    items: int


class BeatPlanOut(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    officer_id: uuid.UUID
    plan_date: date
    status: str = Field(description="generated | edited")
    target: int
    items: list[BeatItemOut]
    villages: list[BeatVillageOut] = Field(description="Villages in the order first visited.")
    generated_at: datetime
    edited_at: datetime | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: BeatPlan) -> BeatPlanOut:
        items = [BeatItemOut.model_validate(i) for i in row.items or []]
        order: dict[uuid.UUID, BeatVillageOut] = {}
        for item in items:
            village = order.get(item.village_id)
            if village is None:
                order[item.village_id] = BeatVillageOut(
                    village_id=item.village_id, village_name=item.village_name, items=1
                )
            else:
                village.items += 1
        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            officer_id=row.officer_id,
            plan_date=row.plan_date,
            status=row.status,
            target=row.target,
            items=items,
            villages=list(order.values()),
            generated_at=row.generated_at,
            edited_at=row.edited_at,
            created_at=row.created_at,
            updated_at=row.updated_at,
            deleted_at=row.deleted_at,
            version=row.version,
        )


class BeatItemIn(BaseModel):
    id: uuid.UUID | None = Field(
        default=None, description="An existing item's id (keeps its reasons); omit to add."
    )
    kind: Literal["farmer", "village"] = "farmer"
    farmer_id: uuid.UUID | None = None
    village_id: uuid.UUID | None = None
    note: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _target(self) -> BeatItemIn:
        if self.id is None and self.kind == "farmer" and self.farmer_id is None:
            raise ValueError("a new farmer item needs farmer_id")
        if self.id is None and self.kind == "village" and self.village_id is None:
            raise ValueError("a new village item needs village_id")
        return self


class BeatPlanUpdate(BaseModel):
    """The whole ordered list: reorder by order, remove by omission, add without ``id``."""

    items: list[BeatItemIn] = Field(max_length=100)
    version: int | None = Field(default=None, description="Optimistic check (409 on mismatch).")


__all__ = [
    "BeatItemIn",
    "BeatItemOut",
    "BeatPlanOut",
    "BeatPlanUpdate",
    "BeatReason",
    "BeatVillageOut",
    "ReasonCode",
]
