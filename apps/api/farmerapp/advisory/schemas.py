"""Request / response models of the farmer advisory APIs (FM-007, FM-008, FM-009, AN-006)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from farmerapp.advisory.models import CropPlotTask, CropTaskTemplate, TaskStatus, TaskType
from farmerapp.catalog.models import ProductCategory
from farmerapp.farmers.models import CropStage, Season

LocalizedText = dict[str, str]


# --------------------------------------------------------------------------- FM-007
class CropPlotTaskOut(BaseModel):
    """One calendar task (also the ``crop_plot_task`` sync entity)."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    crop_plot_id: uuid.UUID
    farmer_id: uuid.UUID
    template_id: uuid.UUID | None
    task_key: str
    task_type: TaskType
    stage: str | None
    due_date: date
    end_date: date
    titles: LocalizedText
    instructions: LocalizedText
    product_category: str | None
    sort_order: int
    status: TaskStatus
    done_at: datetime | None
    reminder_enabled: bool
    reminded_at: datetime | None
    basis_sowing_date: date
    version: int
    updated_at: datetime
    deleted_at: datetime | None

    @classmethod
    def from_row(cls, row: CropPlotTask) -> CropPlotTaskOut:
        return cls.model_validate(row)


class CalendarPlotOut(BaseModel):
    crop_plot_id: uuid.UUID
    farm_id: uuid.UUID
    crop_id: uuid.UUID
    crop_code: str
    crop_names: LocalizedText
    season: str
    sowing_date: date
    tasks: list[CropPlotTaskOut]


class CalendarOut(BaseModel):
    """A farmer's calendar: every active crop plot with its tasks (oldest due first)."""

    farmer_id: uuid.UUID
    today: date = Field(description="Today in IST (the app shows overdue / today / upcoming).")
    plots: list[CalendarPlotOut]


class TaskUpdateIn(BaseModel):
    """Mark a task done (or undo it) and / or switch its reminder."""

    model_config = ConfigDict(extra="forbid")

    status: TaskStatus | None = None
    reminder_enabled: bool | None = None
    version: int | None = Field(default=None, description="Optimistic lock (409 on mismatch).")

    @model_validator(mode="after")
    def _something(self) -> TaskUpdateIn:
        if self.status is None and self.reminder_enabled is None:
            raise ValueError("send status and / or reminder_enabled")
        return self


class TemplateOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    crop_id: uuid.UUID
    season: str | None
    task_key: str
    task_type: TaskType
    day_offset: int
    duration_days: int
    stage: str | None
    titles: LocalizedText
    instructions: LocalizedText
    product_category: str | None
    sort_order: int
    active: bool
    source: str | None
    version: int
    updated_at: datetime

    @classmethod
    def from_row(cls, row: CropTaskTemplate) -> TemplateOut:
        return cls.model_validate(row)


class TemplateListOut(BaseModel):
    items: list[TemplateOut]


def _needs_en(texts: LocalizedText | None) -> LocalizedText | None:
    if texts is not None and not texts.get("en"):
        raise ValueError("an English text ('en') is required (the apps fall back to it)")
    return texts


class TemplateCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    crop_id: uuid.UUID
    season: Season | None = None
    task_key: str = Field(pattern=r"^[a-z0-9_.-]{2,64}$")
    task_type: TaskType
    day_offset: int = Field(ge=-60, le=400, description="Days from sowing / transplanting.")
    duration_days: int = Field(default=1, ge=1, le=60)
    stage: CropStage | None = None
    titles: LocalizedText
    instructions: LocalizedText = Field(default_factory=dict)
    product_category: ProductCategory | None = None
    sort_order: int = Field(default=0, ge=0, le=10_000)
    active: bool = True

    @model_validator(mode="after")
    def _english(self) -> TemplateCreate:
        _needs_en(self.titles)
        return self


class TemplateUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    task_type: TaskType | None = None
    day_offset: int | None = Field(default=None, ge=-60, le=400)
    duration_days: int | None = Field(default=None, ge=1, le=60)
    stage: CropStage | None = None
    titles: LocalizedText | None = None
    instructions: LocalizedText | None = None
    product_category: ProductCategory | None = None
    sort_order: int | None = Field(default=None, ge=0, le=10_000)
    active: bool | None = None
    version: int | None = None

    @model_validator(mode="after")
    def _english(self) -> TemplateUpdate:
        _needs_en(self.titles)
        return self


# --------------------------------------------------------------------------- FM-008
class DailyForecastOut(BaseModel):
    date: date
    temperature_max_c: float | None
    temperature_min_c: float | None
    precipitation_mm: float | None
    precipitation_probability_pct: int | None
    wind_max_kmh: float | None
    weather_code: int | None


class HourlyForecastOut(BaseModel):
    time: datetime
    temperature_c: float | None
    relative_humidity_pct: int | None
    precipitation_probability_pct: int | None
    precipitation_mm: float | None
    wind_kmh: float | None
    wind_gust_kmh: float | None


Advice = Literal["good", "avoid"]
AvoidReason = Literal["rain_likely", "rain", "wind_high"]
Caution = Literal["heat", "humidity_high", "humidity_low"]


class SprayWindowOut(BaseModel):
    start: datetime
    end: datetime
    advice: Advice
    reasons: list[AvoidReason] = Field(description="Why the window is hidden (avoid).")
    cautions: list[Caution] = Field(description="Spraying is possible, with care.")
    max_precipitation_probability_pct: int | None
    precipitation_mm: float | None
    max_wind_kmh: float | None
    max_temperature_c: float | None
    min_relative_humidity_pct: int | None
    max_relative_humidity_pct: int | None


class SprayThresholdsOut(BaseModel):
    max_rain_probability_pct: int
    max_rain_mm: float
    max_wind_kmh: float
    caution_max_temperature_c: float
    caution_max_humidity_pct: int
    caution_min_humidity_pct: int


class SprayAdviceOut(BaseModel):
    windows: list[SprayWindowOut] = Field(
        description="Good 3-hour windows only: windows with rain or wind at or above the "
        "thresholds are hidden (listed in `avoided`)."
    )
    avoided: list[SprayWindowOut]
    thresholds: SprayThresholdsOut


class WeatherOut(BaseModel):
    farm_id: uuid.UUID
    latitude: float = Field(description="The 0.1-degree grid cell sent to the provider.")
    longitude: float
    location_source: Literal["farm", "village"]
    provider: str
    fetched_at: datetime
    cached: bool
    timezone: str = "Asia/Kolkata"
    daily: list[DailyForecastOut]
    hourly: list[HourlyForecastOut]
    spray: SprayAdviceOut


# --------------------------------------------------------------------------- FM-009 / AN-006
class OutbreakAlertOut(BaseModel):
    id: uuid.UUID
    district: str
    crop_id: uuid.UUID
    crop_code: str
    crop_names: LocalizedText
    problem_id: uuid.UUID
    problem_code: str | None
    problem_type: str
    problem_names: LocalizedText
    week_start: date
    iso_year: int
    iso_week: int
    case_count: int
    farmers_affected: int
    baseline_mean: float
    status: str
    grows_crop: bool | None = Field(
        default=None, description="Farmer callers: whether one of their plots has this crop."
    )
    created_at: datetime


class AlertListOut(BaseModel):
    districts: list[str]
    items: list[OutbreakAlertOut]


class CropHealthCellOut(BaseModel):
    district: str
    week_start: date
    crop_id: uuid.UUID
    crop_code: str
    problem_id: uuid.UUID
    problem_code: str | None
    problem_type: str
    confirmed_cases: int
    farmers_affected: int
    prior_mean: float
    outbreak: bool
    alert_id: uuid.UUID | None


class CropHealthOut(BaseModel):
    """AN-006: confirmed problems by district and ISO week with the outbreak flag
    (district level only; no farm locations)."""

    weeks: int
    from_week: date
    to_week: date
    rule: dict[str, Any]
    items: list[CropHealthCellOut]


__all__ = [
    "AlertListOut",
    "CalendarOut",
    "CalendarPlotOut",
    "CropHealthCellOut",
    "CropHealthOut",
    "CropPlotTaskOut",
    "DailyForecastOut",
    "HourlyForecastOut",
    "OutbreakAlertOut",
    "SprayAdviceOut",
    "SprayThresholdsOut",
    "SprayWindowOut",
    "TaskUpdateIn",
    "TemplateCreate",
    "TemplateListOut",
    "TemplateOut",
    "TemplateUpdate",
    "WeatherOut",
]
