"""Reference data for the M7 rules: the Telangana crop calendar (VA-F05) and demo service
areas (VA-F04). Seeded by ``python -m farmerapp.jobs seed`` for the demo tenants.

**Crop calendar** (state-wide rows, ``district`` NULL): sowing windows of the six pilot crops
in the kharif (vanakalam) and rabi (yasangi) seasons, from the Telangana agriculture
department's season advisories and PJTSAU crop production guides as generally published
(transplanting for paddy and chilli counts as sowing). TODO-HUMAN: the tenant agronomist
reviews the windows and adds district rows where a district differs.

**Service area**: the demo tenants' districts as generous bounding boxes (+/- 0.4 degrees,
about 45 km) around each store. TODO-HUMAN: real district polygons (Survey of India / LGD
boundaries) replace them per tenant through ``PATCH /v1/settings`` (``service_area``).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.rules.models import CropCalendar

#: Vehicle-registration style state codes for district codes (TG-WGL).
STATE_CODES = {"Telangana": "TG", "Karnataka": "KA", "Andhra Pradesh": "AP", "Maharashtra": "MH"}
CALENDAR_SOURCE = "Telangana season advisories / PJTSAU crop guides (assumption, M7)"


@dataclass(frozen=True)
class Window:
    crop_code: str
    season: str
    sow_start: str  # MM-DD
    sow_end: str  # MM-DD (may wrap the new year)


#: SPEC 0.3 pilot crops x season, Telangana (state-wide).
TELANGANA_CROP_CALENDAR: tuple[Window, ...] = (
    Window("paddy", "kharif", "06-01", "08-15"),
    Window("paddy", "rabi", "11-01", "01-31"),
    Window("cotton", "kharif", "05-25", "07-31"),
    Window("chilli", "kharif", "06-15", "09-15"),
    Window("chilli", "rabi", "10-01", "11-30"),
    Window("maize", "kharif", "06-01", "07-31"),
    Window("maize", "rabi", "10-01", "12-31"),
    Window("tomato", "kharif", "06-01", "08-31"),
    Window("tomato", "rabi", "09-15", "12-31"),
    Window("groundnut", "kharif", "06-01", "07-31"),
    Window("groundnut", "rabi", "10-15", "12-31"),
)


async def seed_crop_calendar(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    state: str = "Telangana",
    windows: Iterable[Window] = TELANGANA_CROP_CALENDAR,
) -> int:
    """Insert the state-wide windows the tenant does not have yet (idempotent)."""
    existing = {
        (crop, season)
        for crop, season in (
            await session.execute(
                select(CropCalendar.crop_code, CropCalendar.season).where(
                    CropCalendar.tenant_id == tenant_id,
                    CropCalendar.state == state,
                    CropCalendar.district.is_(None),
                    CropCalendar.deleted_at.is_(None),
                )
            )
        ).tuples()
    }
    added = 0
    for w in windows:
        if (w.crop_code, w.season) in existing:
            continue
        session.add(
            CropCalendar(
                id=uuid.uuid5(tenant_id, f"crop_calendar:{state}:{w.crop_code}:{w.season}"),
                tenant_id=tenant_id,
                state=state,
                district=None,
                crop_code=w.crop_code,
                season=w.season,
                sow_start=w.sow_start,
                sow_end=w.sow_end,
                source=CALENDAR_SOURCE,
            )
        )
        added += 1
    await session.flush()
    return added


@dataclass(frozen=True)
class StorePoint:
    code: str
    district: str
    state: str
    lon: float
    lat: float


def service_area_setting(
    stores: Iterable[StorePoint], *, margin_deg: float = 0.4
) -> dict[str, Any]:
    """``tenant.settings["service_area"]`` with one bounding box per store district."""
    districts: list[dict[str, Any]] = []
    for s in stores:
        districts.append(
            {
                "code": f"{STATE_CODES.get(s.state, s.state[:2].upper())}-{s.code}",
                "name": s.district,
                "state": s.state,
                "bbox": [
                    round(s.lon - margin_deg, 4),
                    round(s.lat - margin_deg, 4),
                    round(s.lon + margin_deg, 4),
                    round(s.lat + margin_deg, 4),
                ],
            }
        )
    return {"districts": districts}


__all__ = [
    "TELANGANA_CROP_CALENDAR",
    "StorePoint",
    "Window",
    "seed_crop_calendar",
    "service_area_setting",
]
