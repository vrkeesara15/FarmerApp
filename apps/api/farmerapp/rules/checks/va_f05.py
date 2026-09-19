"""VA-F05 — crop plausibility: a crop plot's crop and sowing date against the season and
the district crop calendar (``crop_calendar``, migration 0029).

The window of (crop, season) comes from the farmer's village district row, else the state
row (``district`` NULL). Reasons:

* ``season_mismatch`` — the calendar knows the crop in the farmer's state but not in this
  season (e.g. cotton recorded as rabi in Telangana);
* ``sowing_outside_window`` — the sowing date is more than ``tolerance_days`` outside the
  season's window (windows may wrap the new year: rabi paddy 1 Nov - 31 Jan);
* ``sowing_in_future`` — sown more than ``max_future_days`` after today.

A crop the calendar does not know for the state is not judged (no calendar, no opinion).

Batch (nightly): plots sown in the last ``lookback_days``. One flag per plot
(key ``plot:<id>``) about the farmer.
"""

from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import select

from farmerapp.catalog.crops import Crop
from farmerapp.farmers.models import CropPlot, Farm, Farmer
from farmerapp.rules.checks.common import ist_day
from farmerapp.rules.models import CropCalendar
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.tenants.models import Village

Window = tuple[str, str]  # (MM-DD start, MM-DD end)


def _md(value: str, year: int) -> date | None:
    month, day = (int(p) for p in value.split("-"))
    try:
        return date(year, month, day)
    except ValueError:  # 02-29 outside a leap year
        return date(year, month, day - 1) if day > 28 else None


def in_window(sown: date, window: Window, tolerance_days: int) -> bool:
    """``sown`` within ``[start - tol, end + tol]`` of the window in some year (wrap-aware)."""
    tol = timedelta(days=tolerance_days)
    start_md, end_md = window
    wraps = end_md < start_md
    for year in (sown.year - 1, sown.year, sown.year + 1):
        start = _md(start_md, year)
        end = _md(end_md, year + 1 if wraps else year)
        if start is None or end is None:
            continue
        if start - tol <= sown <= end + tol:
            return True
    return False


@rule("VA-F05")
async def check(ctx: RuleContext) -> list[Finding]:
    tolerance = int(ctx.param("tolerance_days"))
    max_future = int(ctx.param("max_future_days"))
    today = ist_day(ctx.now)
    since = today - timedelta(days=int(ctx.param("lookback_days")))
    calendar: dict[tuple[str, str | None, str, str], Window] = {}
    known: set[tuple[str, str]] = set()  # (state, crop) the calendar has any window for
    for state, district, crop, season, start, end in (
        await ctx.session.execute(
            select(
                CropCalendar.state,
                CropCalendar.district,
                CropCalendar.crop_code,
                CropCalendar.season,
                CropCalendar.sow_start,
                CropCalendar.sow_end,
            ).where(CropCalendar.tenant_id == ctx.tenant_id, CropCalendar.deleted_at.is_(None))
        )
    ).tuples():
        calendar[(state, district, crop, season)] = (start, end)
        known.add((state, crop))
    if not calendar:
        return []
    stmt = (
        select(
            CropPlot.id,
            CropPlot.farm_id,
            CropPlot.season,
            CropPlot.sowing_date,
            Crop.code,
            Farm.farmer_id,
            Village.district,
            Village.state,
        )
        .join(Crop, Crop.id == CropPlot.crop_id)
        .join(Farm, Farm.id == CropPlot.farm_id)
        .join(Farmer, Farmer.id == Farm.farmer_id)
        .join(Village, Village.id == Farmer.village_id)
        .where(
            CropPlot.tenant_id == ctx.tenant_id,
            CropPlot.deleted_at.is_(None),
            Farm.deleted_at.is_(None),
            Farmer.deleted_at.is_(None),
            CropPlot.sowing_date >= since,
        )
        .order_by(CropPlot.id)
    )
    if ctx.subject_ids is not None:
        stmt = stmt.where(Farmer.id.in_(ctx.subject_ids))
    findings: list[Finding] = []
    for plot_id, farm_id, season, sown, crop, farmer_id, district, state in (
        await ctx.session.execute(stmt)
    ).tuples():
        if (state, crop) not in known:
            continue
        window = calendar.get((state, district, crop, season)) or calendar.get(
            (state, None, crop, season)
        )
        reasons: list[str] = []
        if window is None:
            reasons.append("season_mismatch")
        elif not in_window(sown, window, tolerance):
            reasons.append("sowing_outside_window")
        if sown > today + timedelta(days=max_future):
            reasons.append("sowing_in_future")
        if not reasons:
            continue
        findings.append(
            Finding(
                subject_type=Subject.FARMER,
                subject_id=farmer_id,
                key=f"plot:{plot_id}",
                title=f"Crop plot needs review: {crop} ({season}) sown {sown.isoformat()}",
                evidence=Evidence(
                    records=[
                        record("farmer", farmer_id),
                        record("farm", farm_id),
                        record("crop_plot", plot_id),
                    ],
                    metrics={
                        "reasons": reasons,
                        "crop": crop,
                        "season": season,
                        "sowing_date": sown.isoformat(),
                        "window": list(window) if window else None,
                        "tolerance_days": tolerance,
                        "district": district,
                        "state": state,
                    },
                ),
            )
        )
    return findings
