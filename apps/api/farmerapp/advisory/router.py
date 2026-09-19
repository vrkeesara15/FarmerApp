"""Farmer advisory routes (M7 farmer P1).

FM-007 crop calendar
* ``GET /v1/me/calendar`` — the farmer's own calendar (farmer).
* ``GET /v1/farmers/{id}/calendar`` — a farmer's calendar for staff in scope (SPEC 2.6) and
  the farmer themself.
* ``PATCH /v1/calendar/tasks/{id}`` — mark done / undo, reminder on / off (farmer on their
  own tasks, field officer for their farmers).
* ``GET /v1/calendar/templates`` (staff), ``POST`` / ``PATCH`` / ``DELETE`` (agronomist).

FM-008 weather
* ``GET /v1/farms/{id}/weather`` — 7-day daily + 72 h hourly forecast and spray windows.

FM-009 / AN-006
* ``GET /v1/alerts`` — active outbreak alerts: a farmer's district, or any / one district
  for staff.
* ``GET /v1/analytics/crop-health`` — confirmed problems by district and week with outbreak
  flags (tenant-wide roles and agronomists).
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Annotated

from fastapi import APIRouter, Query, Request, Response, status
from sqlalchemy import func, select

from farmerapp.advisory import calendar as cal
from farmerapp.advisory import outbreaks
from farmerapp.advisory.models import CropTaskTemplate, TaskType
from farmerapp.advisory.schemas import (
    AlertListOut,
    CalendarOut,
    CalendarPlotOut,
    CropHealthCellOut,
    CropHealthOut,
    CropPlotTaskOut,
    DailyForecastOut,
    HourlyForecastOut,
    OutbreakAlertOut,
    SprayAdviceOut,
    SprayThresholdsOut,
    SprayWindowOut,
    TaskUpdateIn,
    TemplateCreate,
    TemplateListOut,
    TemplateOut,
    TemplateUpdate,
    WeatherOut,
)
from farmerapp.advisory.weather import (
    WeatherService,
    build_weather_service,
    grid_cell,
    spray_windows,
)
from farmerapp.api.errors import ConflictError, NotFoundError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.catalog.crops import Crop
from farmerapp.db.geo import SRID
from farmerapp.farmers import service as farmers
from farmerapp.farmers.models import Farm, Farmer
from farmerapp.tenants.models import Village
from farmerapp.tenants.settings import get_tenant_settings

router = APIRouter(tags=["advisory"])

STAFF_READ_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.AGRONOMIST,
)
#: A farmer's calendar / a farm's weather: staff in scope and the farmer.
FARMER_DATA_ROLES = (*STAFF_READ_ROLES, Role.FARMER)
TASK_WRITE_ROLES = (Role.FARMER, Role.FIELD_OFFICER)
TEMPLATE_READ_ROLES = (
    Role.AGRONOMIST,
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
)
ALERT_ROLES = FARMER_DATA_ROLES
CROP_HEALTH_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN, Role.AUDITOR, Role.AGRONOMIST)


# --------------------------------------------------------------------------- FM-007
async def _calendar_out(
    session: DbSession, farmer: Farmer, services: Services, plot_id: uuid.UUID | None = None
) -> CalendarOut:
    now = services.clock.now()
    plots = await cal.farmer_calendar(session, farmer, now=now, crop_plot_id=plot_id)
    return CalendarOut(
        farmer_id=farmer.id,
        today=cal.today_ist(now),
        plots=[
            CalendarPlotOut(
                crop_plot_id=p.plot.id,
                farm_id=p.plot.farm_id,
                crop_id=p.crop.id,
                crop_code=p.crop.code,
                crop_names={"en": p.crop.name, **(p.crop.names or {})},
                season=p.plot.season,
                sowing_date=p.plot.sowing_date,
                tasks=[CropPlotTaskOut.from_row(t) for t in p.tasks],
            )
            for p in plots
        ],
    )


@router.get(
    "/me/calendar",
    operation_id="getMyCalendar",
    summary="FM-007: the farmer's crop calendar (every active crop plot and its tasks)",
    response_model=CalendarOut,
    responses=problem_responses((404, "not_found")),
)
async def my_calendar(
    actor: Annotated[User, require_roles(Role.FARMER)], session: DbSession, services: Services
) -> CalendarOut:
    return await _calendar_out(session, await cal.own_farmer(session, actor), services)


@router.get(
    "/farmers/{id}/calendar",
    operation_id="getFarmerCalendar",
    summary="FM-007: a farmer's crop calendar (staff in scope, or the farmer)",
    response_model=CalendarOut,
    responses=problem_responses((404, "not_found")),
)
async def farmer_calendar(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*FARMER_DATA_ROLES)],
    session: DbSession,
    services: Services,
    crop_plot_id: Annotated[uuid.UUID | None, Query()] = None,
) -> CalendarOut:
    farmer = await farmers.visible_farmer(session, actor, id)
    return await _calendar_out(session, farmer, services, crop_plot_id)


@router.patch(
    "/calendar/tasks/{id}",
    operation_id="updateCalendarTask",
    summary="FM-007: mark a task done (or not) and switch its reminder",
    response_model=CropPlotTaskOut,
    responses=problem_responses((404, "not_found"), (409, "version_conflict")),
)
async def update_calendar_task(
    id: uuid.UUID,
    body: TaskUpdateIn,
    actor: Annotated[User, require_roles(*TASK_WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> CropPlotTaskOut:
    task = await cal.visible_task(session, actor, id)
    row = await cal.update_task(
        session,
        actor,
        task,
        status=body.status,
        reminder_enabled=body.reminder_enabled,
        expected_version=body.version,
        now=services.clock.now(),
    )
    return CropPlotTaskOut.from_row(row)


@router.get(
    "/calendar/templates",
    operation_id="listCalendarTemplates",
    summary="FM-007: the agronomist-maintained crop calendar templates",
    response_model=TemplateListOut,
)
async def list_templates(
    actor: Annotated[User, require_roles(*TEMPLATE_READ_ROLES)],
    session: DbSession,
    crop_id: Annotated[uuid.UUID | None, Query()] = None,
    include_inactive: Annotated[bool, Query()] = False,
) -> TemplateListOut:
    stmt = select(CropTaskTemplate).where(
        CropTaskTemplate.tenant_id == actor.tenant_id, CropTaskTemplate.deleted_at.is_(None)
    )
    if crop_id is not None:
        stmt = stmt.where(CropTaskTemplate.crop_id == crop_id)
    if not include_inactive:
        stmt = stmt.where(CropTaskTemplate.active.is_(True))
    rows = await session.scalars(
        stmt.order_by(
            CropTaskTemplate.crop_id,
            CropTaskTemplate.season.nulls_first(),
            CropTaskTemplate.sort_order,
            CropTaskTemplate.task_key,
        )
    )
    return TemplateListOut(items=[TemplateOut.from_row(r) for r in rows])


async def _template(session: DbSession, actor: User, template_id: uuid.UUID) -> CropTaskTemplate:
    row = await session.get(CropTaskTemplate, template_id)
    if row is None or row.tenant_id != actor.tenant_id or row.deleted_at is not None:
        raise NotFoundError("Calendar template not found.")
    return row


@router.post(
    "/calendar/templates",
    operation_id="createCalendarTemplate",
    summary="FM-007: add a task to a crop's calendar (agronomist)",
    response_model=TemplateOut,
    status_code=status.HTTP_201_CREATED,
    responses=problem_responses((404, "not_found"), (409, "template_exists")),
)
async def create_template(
    body: TemplateCreate,
    actor: Annotated[User, require_roles(Role.AGRONOMIST)],
    session: DbSession,
) -> TemplateOut:
    crop = await session.get(Crop, body.crop_id)
    if crop is None or crop.tenant_id != actor.tenant_id or crop.deleted_at is not None:
        raise NotFoundError("Crop not found.")
    season = body.season.value if body.season else None
    clash = await session.scalar(
        select(func.count())
        .select_from(CropTaskTemplate)
        .where(
            CropTaskTemplate.tenant_id == actor.tenant_id,
            CropTaskTemplate.crop_id == body.crop_id,
            func.coalesce(CropTaskTemplate.season, "") == (season or ""),
            CropTaskTemplate.task_key == body.task_key,
            CropTaskTemplate.deleted_at.is_(None),
        )
    )
    if clash:
        raise ConflictError("That task key exists for the crop and season.", code="template_exists")
    row = CropTaskTemplate(
        tenant_id=actor.tenant_id,
        crop_id=body.crop_id,
        season=season,
        task_key=body.task_key,
        task_type=body.task_type.value,
        day_offset=body.day_offset,
        duration_days=body.duration_days,
        stage=body.stage.value if body.stage else None,
        titles=body.titles,
        instructions=body.instructions,
        product_category=body.product_category.value if body.product_category else None,
        sort_order=body.sort_order,
        active=body.active,
        updated_by=actor.id,
    )
    session.add(row)
    await session.flush()
    await session.refresh(row)
    return TemplateOut.from_row(row)


@router.patch(
    "/calendar/templates/{id}",
    operation_id="updateCalendarTemplate",
    summary="FM-007: change a template; pending tasks follow on the next read / job run",
    response_model=TemplateOut,
    responses=problem_responses((404, "not_found"), (409, "version_conflict")),
)
async def update_template(
    id: uuid.UUID,
    body: TemplateUpdate,
    actor: Annotated[User, require_roles(Role.AGRONOMIST)],
    session: DbSession,
) -> TemplateOut:
    row = await _template(session, actor, id)
    if body.version is not None and body.version != row.version:
        raise ConflictError(
            "The template changed since you loaded it.",
            code="version_conflict",
            extra={"current_version": row.version},
        )
    changes = body.model_dump(exclude_unset=True, exclude={"version"}, mode="json")
    for key, value in changes.items():
        setattr(row, key, value)
    row.updated_by = actor.id
    await session.flush()
    await session.refresh(row)
    return TemplateOut.from_row(row)


@router.delete(
    "/calendar/templates/{id}",
    operation_id="deleteCalendarTemplate",
    summary="FM-007: remove a template (soft delete; pending tasks go on the next read)",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    responses=problem_responses((404, "not_found")),
)
async def delete_template(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(Role.AGRONOMIST)],
    session: DbSession,
    services: Services,
) -> Response:
    row = await _template(session, actor, id)
    row.deleted_at = services.clock.now()
    row.updated_by = actor.id
    await session.flush()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --------------------------------------------------------------------------- FM-008
def get_weather(request: Request) -> WeatherService:
    """The app's weather service (built on first use; tests put their own on app.state)."""
    service: WeatherService | None = getattr(request.app.state, "weather", None)
    if service is None:
        service = build_weather_service(request.app.state.auth.settings)
        request.app.state.weather = service
    return service


async def _farm_point(session: DbSession, farm: Farm) -> tuple[float, float, str]:
    if farm.centroid_lat is not None and farm.centroid_lon is not None:
        return float(farm.centroid_lat), float(farm.centroid_lon), "farm"
    from geoalchemy2 import Geometry
    from sqlalchemy import cast

    point = cast(Village.location, Geometry(geometry_type="POINT", srid=SRID))
    row = (
        await session.execute(
            select(func.ST_Y(point), func.ST_X(point))
            .join(Farmer, Farmer.village_id == Village.id)
            .where(Farmer.id == farm.farmer_id)
        )
    ).first()
    if row is None or row[0] is None:  # pragma: no cover - village location is NOT NULL
        raise NotFoundError("The farm has no location.")
    return float(row[0]), float(row[1]), "village"


@router.get(
    "/farms/{id}/weather",
    operation_id="getFarmWeather",
    summary="FM-008: 7-day forecast, next 72 h hourly and 3-hour spray windows at a farm",
    response_model=WeatherOut,
    responses=problem_responses((404, "not_found"), (503, "weather_unavailable")),
)
async def farm_weather(
    id: uuid.UUID,
    request: Request,
    actor: Annotated[User, require_roles(*FARMER_DATA_ROLES)],
    session: DbSession,
    services: Services,
) -> WeatherOut:
    farm = await farmers.visible_farm(session, actor, id)
    lat, lon, source = await _farm_point(session, farm)
    weather = get_weather(request)
    forecast, cached = await weather.cache.get(weather.provider, lat, lon)
    now = services.clock.now()
    thresholds = (await get_tenant_settings(session, actor.tenant_id)).weather
    windows = spray_windows(forecast.hours, thresholds, now=now)
    cell_lat, cell_lon = grid_cell(lat, lon)
    # The hourly window is exactly 72 entries from the current hour (whatever the minute).
    hour_start = now.replace(minute=0, second=0, microsecond=0)
    horizon = hour_start + timedelta(hours=72)

    def window_out(w: object) -> SprayWindowOut:
        return SprayWindowOut.model_validate(w, from_attributes=True)

    return WeatherOut(
        farm_id=farm.id,
        latitude=cell_lat,
        longitude=cell_lon,
        location_source=source,
        provider=forecast.provider,
        fetched_at=forecast.fetched_at,
        cached=cached,
        daily=[DailyForecastOut.model_validate(d, from_attributes=True) for d in forecast.days],
        hourly=[
            HourlyForecastOut.model_validate(h, from_attributes=True)
            for h in forecast.hours
            if hour_start <= h.time < horizon
        ],
        spray=SprayAdviceOut(
            windows=[window_out(w) for w in windows if w.advice == "good"],
            avoided=[window_out(w) for w in windows if w.advice == "avoid"],
            thresholds=SprayThresholdsOut(
                max_rain_probability_pct=thresholds.spray_max_rain_probability_pct,
                max_rain_mm=thresholds.spray_max_rain_mm,
                max_wind_kmh=thresholds.spray_max_wind_kmh,
                caution_max_temperature_c=thresholds.caution_max_temperature_c,
                caution_max_humidity_pct=thresholds.caution_max_humidity_pct,
                caution_min_humidity_pct=thresholds.caution_min_humidity_pct,
            ),
        ),
    )


# --------------------------------------------------------------------------- FM-009
def _alert_out(row: outbreaks.AlertRow, grows: bool | None) -> OutbreakAlertOut:
    a = row.alert
    return OutbreakAlertOut(
        id=a.id,
        district=a.district,
        crop_id=a.crop_id,
        crop_code=row.crop.code,
        crop_names={"en": row.crop.name, **(row.crop.names or {})},
        problem_id=a.problem_id,
        problem_code=row.problem_code,
        problem_type=row.problem.problem_type,
        problem_names=dict(row.problem.names or {}),
        week_start=a.week_start,
        iso_year=a.iso_year,
        iso_week=a.iso_week,
        case_count=a.case_count,
        farmers_affected=a.farmers_affected,
        baseline_mean=float(a.baseline_mean),
        status=a.status,
        grows_crop=grows,
        created_at=a.created_at,
    )


@router.get(
    "/alerts",
    operation_id="listOutbreakAlerts",
    summary="FM-009: active pest and disease alerts (the farmer's district, or by district)",
    response_model=AlertListOut,
    responses=problem_responses((404, "not_found")),
)
async def list_alerts(
    actor: Annotated[User, require_roles(*ALERT_ROLES)],
    session: DbSession,
    services: Services,
    district: Annotated[str | None, Query(max_length=80)] = None,
    crop_id: Annotated[uuid.UUID | None, Query()] = None,
) -> AlertListOut:
    today = cal.today_ist(services.clock.now())
    rule = (await get_tenant_settings(session, actor.tenant_id)).outbreak
    grows: set[uuid.UUID] | None = None
    districts: list[str] | None
    if UserRole(actor.role) == UserRole.FARMER:
        farmer = await cal.own_farmer(session, actor)
        districts, grows = await outbreaks.farmer_districts_and_crops(session, farmer, today)
    else:
        districts = [district] if district else None
    rows = await outbreaks.active_alerts(
        session, actor.tenant_id, districts=districts, today=today, rule=rule, crop_id=crop_id
    )
    return AlertListOut(
        districts=districts or sorted({r.alert.district for r in rows}),
        items=[_alert_out(r, None if grows is None else r.alert.crop_id in grows) for r in rows],
    )


@router.get(
    "/analytics/crop-health",
    operation_id="getCropHealth",
    summary="AN-006: confirmed problems by district and ISO week with outbreak flags",
    response_model=CropHealthOut,
)
async def crop_health(
    actor: Annotated[User, require_roles(*CROP_HEALTH_ROLES)],
    session: DbSession,
    services: Services,
    weeks: Annotated[int, Query(ge=1, le=52)] = 8,
    district: Annotated[str | None, Query(max_length=80)] = None,
    crop_id: Annotated[uuid.UUID | None, Query()] = None,
) -> CropHealthOut:
    today = cal.today_ist(services.clock.now())
    week_list, rule, cells = await outbreaks.crop_health(
        session, actor.tenant_id, today=today, weeks=weeks, district=district, crop_id=crop_id
    )
    return CropHealthOut(
        weeks=weeks,
        from_week=week_list[0],
        to_week=week_list[-1],
        rule=rule.model_dump(mode="json"),
        items=[
            CropHealthCellOut(
                district=h.cell.district,
                week_start=h.cell.week_start,
                crop_id=h.cell.crop_id,
                crop_code=h.crop_code,
                problem_id=h.cell.problem_id,
                problem_code=h.problem_code,
                problem_type=h.problem_type,
                confirmed_cases=h.cell.cases,
                farmers_affected=h.cell.farmers,
                prior_mean=h.cell.prior_mean,
                outbreak=h.cell.fires,
                alert_id=h.alert_id,
            )
            for h in cells
        ],
    )


__all__ = [
    "ALERT_ROLES",
    "CROP_HEALTH_ROLES",
    "FARMER_DATA_ROLES",
    "TASK_WRITE_ROLES",
    "TEMPLATE_READ_ROLES",
    "TaskType",
    "get_weather",
    "router",
]
