"""Farmer registration and edits (FA-012, FA-013) — the one write path behind the REST
endpoints and ``POST /v1/sync`` (FA-025).

Every function takes the acting ``User`` and enforces the SPEC 2.6 row scope through
``farmer_filters`` (a farmer the actor cannot see does not exist: 404), raises ``AppError``
problems for validation and conflicts, and returns the read models of ``schemas.py`` so
both callers answer with the same shape.

Inline checks (SPEC 6.2, cheap ones only — the batch agents come in M4):

* VA-F01 — E.164 Indian mobile (schema), duplicate ``(tenant, phone)`` -> 409
  ``farmer_phone_exists``, staff phone -> 422 ``farmer_phone_is_staff``, OTP verification
  through ``phone_verification_token`` (``phone_verify.py``).
* VA-F03 — polygon validity (``ST_IsValid``) -> 422 ``farm_boundary_invalid``; declared vs
  measured acres outside ±30 % -> warning ``area_mismatch``; overlap with another farmer's
  farm above 20 % -> warning ``farm_overlap``. Warnings never reject: the console review
  queue picks them up.

M4: after every registration and farm write the inline rules of the engine run on the
farmer in the same transaction (``_validate``: VA-F01, VA-F02, VA-F03 raise flags for the
store manager next to the warnings above) and a registration emits ``farmer.registered``
for the event rules (VA-F06). The engine isolates each rule in a savepoint: a failing rule
never fails the write.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import ForbiddenError, NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.scope import farmer_filters
from farmerapp.catalog.crops import Crop
from farmerapp.db.models import Tenant
from farmerapp.farmers.errors import (
    FarmBoundaryInvalidError,
    FarmerPhoneExistsError,
    FarmerPhoneIsStaffError,
    VersionConflictError,
)
from farmerapp.farmers.models import (
    DEFAULT_CONSENT_VERSION,
    ConsentChannel,
    ConsentPurpose,
    ConsentRecord,
    ConsentSubject,
    CropPlot,
    Farm,
    Farmer,
    FarmerSource,
    FarmPhoto,
)
from farmerapp.farmers.phone_verify import verify_token
from farmerapp.farmers.schemas import (
    ConsentIn,
    ConsentRecordOut,
    CropPlotCreate,
    CropPlotOut,
    CropPlotUpdate,
    FarmCreate,
    FarmerCreate,
    FarmerDetailOut,
    FarmerOut,
    FarmerUpdate,
    FarmOut,
    FarmUpdate,
    GeoJsonPolygon,
)
from farmerapp.rules import engine as rules_engine
from farmerapp.rules.schema import Subject
from farmerapp.settings import Settings
from farmerapp.tenants.models import Village
from farmerapp.uploads.blobstore import parse_uri
from farmerapp.uploads.models import UploadSession, UploadStatus

AREA_TOLERANCE = Decimal("0.30")  # VA-F03: declared vs measured within ±30 %
OVERLAP_THRESHOLD = 0.20  # VA-F03: overlap with another farmer's farm above 20 %
ACRE_M2 = Decimal("4046.8564224")

WARNING_AREA_MISMATCH = "area_mismatch"
WARNING_FARM_OVERLAP = "farm_overlap"


@dataclass
class Warnings:
    """Collects VA-F03 warnings per farm; ``all`` is the deduplicated union."""

    by_farm: dict[uuid.UUID, list[str]] = field(default_factory=dict)

    def add(self, farm_id: uuid.UUID, warning: str) -> None:
        self.by_farm.setdefault(farm_id, []).append(warning)

    def of(self, farm_id: uuid.UUID) -> list[str]:
        return list(self.by_farm.get(farm_id, ()))

    @property
    def all(self) -> list[str]:
        seen: list[str] = []
        for warnings in self.by_farm.values():
            seen.extend(w for w in warnings if w not in seen)
        return seen


def _now() -> datetime:
    return datetime.now(UTC)


def _is_farmer(actor: User) -> bool:
    return UserRole(actor.role) == UserRole.FARMER


# --------------------------------------------------------------------------- lookups
async def visible_farmer(session: AsyncSession, actor: User, farmer_id: uuid.UUID) -> Farmer:
    """The farmer if it exists and is within the actor's 2.6 scope; else 404."""
    stmt = select(Farmer).where(
        Farmer.id == farmer_id, Farmer.deleted_at.is_(None), *farmer_filters(actor)
    )
    farmer = (await session.execute(stmt)).scalar_one_or_none()
    if farmer is None:
        raise NotFoundError("Farmer not found.")
    return farmer


async def visible_farm(session: AsyncSession, actor: User, farm_id: uuid.UUID) -> Farm:
    stmt = (
        select(Farm)
        .join(Farmer, Farmer.id == Farm.farmer_id)
        .where(
            Farm.id == farm_id,
            Farm.deleted_at.is_(None),
            Farmer.deleted_at.is_(None),
            *farmer_filters(actor),
        )
    )
    farm = (await session.execute(stmt)).scalar_one_or_none()
    if farm is None:
        raise NotFoundError("Farm not found.")
    return farm


async def visible_crop_plot(session: AsyncSession, actor: User, plot_id: uuid.UUID) -> CropPlot:
    stmt = (
        select(CropPlot)
        .join(Farm, Farm.id == CropPlot.farm_id)
        .join(Farmer, Farmer.id == Farm.farmer_id)
        .where(
            CropPlot.id == plot_id,
            CropPlot.deleted_at.is_(None),
            Farm.deleted_at.is_(None),
            Farmer.deleted_at.is_(None),
            *farmer_filters(actor),
        )
    )
    plot = (await session.execute(stmt)).scalar_one_or_none()
    if plot is None:
        raise NotFoundError("Crop plot not found.")
    return plot


async def _village(session: AsyncSession, tenant_id: uuid.UUID, village_id: uuid.UUID) -> Village:
    village = await session.get(Village, village_id)
    if village is None or village.tenant_id != tenant_id or village.deleted_at is not None:
        raise NotFoundError("Village not found.")
    return village


async def _crop(session: AsyncSession, tenant_id: uuid.UUID, crop_id: uuid.UUID) -> Crop:
    crop = await session.get(Crop, crop_id)
    if crop is None or crop.tenant_id != tenant_id or crop.deleted_at is not None:
        raise NotFoundError("Crop not found.")
    return crop


async def _consent_version(session: AsyncSession, tenant_id: uuid.UUID) -> str:
    tenant = await session.get(Tenant, tenant_id)
    value = (tenant.settings or {}).get("consent_version") if tenant is not None else None
    return str(value) if value else DEFAULT_CONSENT_VERSION


def _check_version(row: Any, expected: int | None) -> None:
    if expected is not None and expected != row.version:
        raise VersionConflictError(
            f"Version {expected} is stale; the current version is {row.version}.",
            extra={"current_version": row.version},
        )


# --------------------------------------------------------------------------- M4 rules
FARMER_REGISTERED = "farmer.registered"


async def _validate(
    session: AsyncSession, tenant_id: uuid.UUID, farmer_id: uuid.UUID, *, registered: bool = False
) -> None:
    """Inline rules on the farmer (and ``farmer.registered`` event rules for a new one)."""
    await rules_engine.run_inline(session, tenant_id, Subject.FARMER, [farmer_id])
    if registered:
        await rules_engine.emit(session, tenant_id, FARMER_REGISTERED, [farmer_id])


# --------------------------------------------------------------------------- VA-F01
async def _check_phone(session: AsyncSession, tenant_id: uuid.UUID, phone: str) -> None:
    exists = await session.scalar(
        select(Farmer.id).where(Farmer.tenant_id == tenant_id, Farmer.phone == phone).limit(1)
    )
    if exists is not None:
        raise FarmerPhoneExistsError("A farmer with this phone is already registered.")
    staff = await session.scalar(
        select(User.id)
        .where(
            User.tenant_id == tenant_id,
            User.phone == phone,
            User.role != UserRole.FARMER,
            User.deleted_at.is_(None),
        )
        .limit(1)
    )
    if staff is not None:
        raise FarmerPhoneIsStaffError("This phone belongs to a staff account.")


# --------------------------------------------------------------------------- VA-F03
async def check_boundary(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    farmer_id: uuid.UUID,
    boundary: GeoJsonPolygon,
    declared_acres: Decimal,
) -> list[str]:
    """Reject invalid polygons; return the soft warnings for a valid one."""
    ewkt = boundary.ewkt()
    geom = func.ST_GeomFromEWKT(ewkt)
    geog = func.ST_GeogFromText(ewkt)
    valid, reason, area_m2 = (
        await session.execute(
            select(func.ST_IsValid(geom), func.ST_IsValidReason(geom), func.ST_Area(geog))
        )
    ).one()
    if not valid:
        raise FarmBoundaryInvalidError(f"Farm boundary is not a valid polygon: {reason}.")
    warnings: list[str] = []
    measured = Decimal(str(area_m2)) / ACRE_M2
    if measured <= 0 or abs(measured - declared_acres) / declared_acres > AREA_TOLERANCE:
        warnings.append(WARNING_AREA_MISMATCH)
    overlap_m2 = await session.scalar(
        select(
            func.coalesce(func.max(func.ST_Area(func.ST_Intersection(Farm.boundary, geog))), 0.0)
        )
        .join(Farmer, Farmer.id == Farm.farmer_id)
        .where(
            Farm.tenant_id == tenant_id,
            Farm.farmer_id != farmer_id,
            Farm.deleted_at.is_(None),
            Farmer.deleted_at.is_(None),
            Farm.boundary.is_not(None),
            func.ST_Intersects(Farm.boundary, geog),
        )
    )
    if area_m2 and float(overlap_m2 or 0.0) / float(area_m2) > OVERLAP_THRESHOLD:
        warnings.append(WARNING_FARM_OVERLAP)
    return warnings


# --------------------------------------------------------------------------- photos
async def _photo_rows(
    session: AsyncSession, tenant_id: uuid.UUID, farm_id: uuid.UUID, uris: list[str]
) -> list[FarmPhoto]:
    """``farm_photo`` rows for completed uploads of this tenant (sha256 copied from the
    upload session; a URI outside the tenant's prefix is rejected)."""
    rows: list[FarmPhoto] = []
    for uri in dict.fromkeys(uris):
        try:
            _bucket, key = parse_uri(uri)
        except ValueError as exc:
            raise NotFoundError(f"Unknown blob {uri}.") from exc
        if not key.startswith(f"{tenant_id}/"):
            raise NotFoundError(f"Unknown blob {uri}.")
        upload = (
            await session.execute(
                select(UploadSession)
                .where(
                    UploadSession.tenant_id == tenant_id,
                    UploadSession.blob_uri == uri,
                    UploadSession.status == UploadStatus.COMPLETE,
                )
                .limit(1)
            )
        ).scalar_one_or_none()
        rows.append(
            FarmPhoto(
                tenant_id=tenant_id,
                created_at=_now(),
                farm_id=farm_id,
                blob_uri=uri,
                sha256=upload.sha256 if upload is not None else None,
                taken_at=upload.created_at if upload is not None else None,
            )
        )
    return rows


async def _photos(
    session: AsyncSession, farm_ids: list[uuid.UUID]
) -> dict[uuid.UUID, list[FarmPhoto]]:
    out: dict[uuid.UUID, list[FarmPhoto]] = {f: [] for f in farm_ids}
    if farm_ids:
        rows = (
            await session.execute(
                select(FarmPhoto)
                .where(FarmPhoto.farm_id.in_(farm_ids), FarmPhoto.deleted_at.is_(None))
                .order_by(FarmPhoto.created_at, FarmPhoto.id)
            )
        ).scalars()
        for photo in rows:
            out[photo.farm_id].append(photo)
    return out


# --------------------------------------------------------------------------- read helpers
async def farm_out(session: AsyncSession, farm: Farm, warnings: list[str] | None = None) -> FarmOut:
    await session.refresh(farm)
    plots = (
        (
            await session.execute(
                select(CropPlot)
                .where(CropPlot.farm_id == farm.id, CropPlot.deleted_at.is_(None))
                .order_by(CropPlot.sowing_date, CropPlot.created_at, CropPlot.id)
            )
        )
        .scalars()
        .all()
    )
    photos = await _photos(session, [farm.id])
    return FarmOut.from_row(farm, list(plots), photos[farm.id], warnings)


async def farmer_detail(
    session: AsyncSession,
    farmer: Farmer,
    *,
    redact_pii: bool = False,
    warnings: Warnings | None = None,
) -> FarmerDetailOut:
    """The farmer 360: farms with crop plots and photos, consent history."""
    await session.refresh(farmer)
    farms = (
        (
            await session.execute(
                select(Farm)
                .where(Farm.farmer_id == farmer.id, Farm.deleted_at.is_(None))
                .order_by(Farm.created_at, Farm.id)
            )
        )
        .scalars()
        .all()
    )
    plots_by_farm: dict[uuid.UUID, list[CropPlot]] = {f.id: [] for f in farms}
    if farms:
        plots = (
            await session.execute(
                select(CropPlot)
                .where(CropPlot.farm_id.in_(list(plots_by_farm)), CropPlot.deleted_at.is_(None))
                .order_by(CropPlot.sowing_date, CropPlot.created_at, CropPlot.id)
            )
        ).scalars()
        for plot in plots:
            plots_by_farm[plot.farm_id].append(plot)
    photos = await _photos(session, list(plots_by_farm))
    consents = (
        (
            await session.execute(
                select(ConsentRecord)
                .where(ConsentRecord.subject_id == farmer.id)
                .order_by(ConsentRecord.created_at, ConsentRecord.id)
            )
        )
        .scalars()
        .all()
    )
    warnings = warnings or Warnings()
    base = FarmerOut.from_row(farmer, redact_pii=redact_pii)
    return FarmerDetailOut(
        **base.model_dump(),
        farms=[
            FarmOut.from_row(f, plots_by_farm[f.id], photos[f.id], warnings.of(f.id)) for f in farms
        ],
        consents=[ConsentRecordOut.from_row(c) for c in consents],
        warnings=warnings.all,
    )


# --------------------------------------------------------------------------- consent
async def add_consent(
    session: AsyncSession,
    actor: User,
    farmer: Farmer,
    body: ConsentIn,
    *,
    record_id: uuid.UUID | None = None,
    version: str | None = None,
    touch_farmer: bool = True,
) -> ConsentRecordOut:
    """Append a grant or a withdrawal and refresh the farmer's cached consent state
    (``touch_farmer=False`` when the caller already set it, e.g. at registration)."""
    now = _now()
    version = version or await _consent_version(session, farmer.tenant_id)
    record = ConsentRecord(
        id=record_id or uuid.uuid4(),
        tenant_id=farmer.tenant_id,
        created_at=now,
        subject_type=ConsentSubject.FARMER,
        subject_id=farmer.id,
        purpose=body.purpose,
        version=version,
        language=body.language or farmer.language,
        granted_at=now if body.granted else None,
        withdrawn_at=None if body.granted else now,
        channel=ConsentChannel.APP if _is_farmer(actor) else ConsentChannel.OFFICER,
        recorded_by=actor.id,
    )
    session.add(record)
    if touch_farmer:
        if body.purpose == ConsentPurpose.MARKETING:
            farmer.consent_marketing = body.granted
        farmer.consent_version = version
    await session.flush()
    return ConsentRecordOut.from_row(record)


# --------------------------------------------------------------------------- farmer
async def create_farmer(
    session: AsyncSession,
    actor: User,
    body: FarmerCreate,
    *,
    settings: Settings,
    now: datetime | None = None,
) -> FarmerDetailOut:
    """``now`` is the auth clock (token expiry is checked against it); default: wall clock."""
    if _is_farmer(actor):
        raise ForbiddenError("Farmers cannot register other farmers.")
    tenant_id = actor.tenant_id
    await _check_phone(session, tenant_id, body.phone)
    await _village(session, tenant_id, body.village_id)
    verified = False
    if body.phone_verification_token is not None:
        verify_token(
            settings,
            body.phone_verification_token,
            tenant_id=tenant_id,
            phone=body.phone,
            now=now or _now(),
        )
        verified = True
    consent_version = await _consent_version(session, tenant_id) if body.consents else None
    marketing = next(
        (c.granted for c in body.consents if c.purpose == ConsentPurpose.MARKETING), False
    )
    farmer = Farmer(
        id=body.id or uuid.uuid4(),
        created_at=_now(),
        tenant_id=tenant_id,
        phone=body.phone,
        phone_last4=Farmer.last4(body.phone),
        phone_verified=verified,
        name=body.name,
        village_id=body.village_id,
        landmark=body.landmark,
        language=body.language,
        land_ownership=body.land_ownership,
        registered_by=actor.id,
        source=FarmerSource.OFFICER,
        consent_marketing=marketing,
        consent_version=consent_version,
    )
    session.add(farmer)
    await session.flush()
    warnings = Warnings()
    for farm_body in body.farms:
        farm, farm_warnings = await _add_farm(session, farmer, farm_body)
        for w in farm_warnings:
            warnings.add(farm.id, w)
    for consent in body.consents:
        await add_consent(
            session, actor, farmer, consent, version=consent_version, touch_farmer=False
        )
    await session.flush()
    await _validate(session, tenant_id, farmer.id, registered=True)
    return await farmer_detail(session, farmer, warnings=warnings)


async def update_farmer(
    session: AsyncSession, actor: User, farmer: Farmer, body: FarmerUpdate
) -> FarmerOut:
    _check_version(farmer, body.version)
    changes = body.model_dump(exclude_unset=True, exclude={"version"})
    if "village_id" in changes and changes["village_id"] is not None:
        await _village(session, farmer.tenant_id, changes["village_id"])
    for key, value in changes.items():
        setattr(farmer, key, value)
    await session.flush()
    if {"name", "village_id"} & set(changes):
        await _validate(session, farmer.tenant_id, farmer.id)
    await session.refresh(farmer)
    return FarmerOut.from_row(farmer)


async def mark_phone_verified(session: AsyncSession, farmer: Farmer) -> FarmerOut:
    farmer.phone_verified = True
    await session.flush()
    await session.refresh(farmer)
    return FarmerOut.from_row(farmer)


# --------------------------------------------------------------------------- farm
async def _add_farm(
    session: AsyncSession, farmer: Farmer, body: FarmCreate
) -> tuple[Farm, list[str]]:
    farm_id = body.id or uuid.uuid4()
    warnings: list[str] = []
    if body.boundary is not None:
        warnings = await check_boundary(
            session,
            tenant_id=farmer.tenant_id,
            farmer_id=farmer.id,
            boundary=body.boundary,
            declared_acres=body.area_acres,
        )
    farm = Farm(
        id=farm_id,
        created_at=_now(),
        tenant_id=farmer.tenant_id,
        farmer_id=farmer.id,
        name=body.name,
        survey_no=body.survey_no,
        boundary=body.boundary.ewkt() if body.boundary is not None else None,
        area_acres=body.area_acres,
        soil=body.soil,
        irrigation=body.irrigation,
        ownership=body.ownership,
    )
    session.add(farm)
    await session.flush()
    for plot_body in body.crop_plots:
        await _add_crop_plot(session, farm, plot_body)
    session.add_all(await _photo_rows(session, farmer.tenant_id, farm.id, body.photos))
    await session.flush()
    return farm, warnings


async def add_farm(session: AsyncSession, actor: User, farmer: Farmer, body: FarmCreate) -> FarmOut:
    if _is_farmer(actor) and farmer.user_id != actor.id:
        raise NotFoundError("Farmer not found.")
    farm, warnings = await _add_farm(session, farmer, body)
    await _validate(session, farmer.tenant_id, farmer.id)
    return await farm_out(session, farm, warnings)


async def update_farm(session: AsyncSession, actor: User, farm: Farm, body: FarmUpdate) -> FarmOut:
    _check_version(farm, body.version)
    changes = body.model_dump(exclude_unset=True, exclude={"version", "boundary", "photos"})
    warnings: list[str] = []
    boundary_set = "boundary" in body.model_fields_set
    if boundary_set and body.boundary is not None:
        declared = body.area_acres if body.area_acres is not None else farm.area_acres
        warnings = await check_boundary(
            session,
            tenant_id=farm.tenant_id,
            farmer_id=farm.farmer_id,
            boundary=body.boundary,
            declared_acres=declared,
        )
        farm.boundary = body.boundary.ewkt()
    elif boundary_set:
        farm.boundary = None
    for key, value in changes.items():
        setattr(farm, key, value)
    if body.photos is not None:
        existing = await _photos(session, [farm.id])
        for photo in existing[farm.id]:
            if photo.blob_uri not in body.photos:
                photo.deleted_at = _now()
        known = {p.blob_uri for p in existing[farm.id]}
        new_uris = [u for u in body.photos if u not in known]
        session.add_all(await _photo_rows(session, farm.tenant_id, farm.id, new_uris))
    await session.flush()
    if boundary_set or "area_acres" in changes:
        await _validate(session, farm.tenant_id, farm.farmer_id)
    return await farm_out(session, farm, warnings)


async def delete_farm(
    session: AsyncSession, farm: Farm, *, expected_version: int | None = None
) -> FarmOut:
    _check_version(farm, expected_version)
    now = _now()
    farm.deleted_at = now
    plots = (
        await session.execute(
            select(CropPlot).where(CropPlot.farm_id == farm.id, CropPlot.deleted_at.is_(None))
        )
    ).scalars()
    for plot in plots:
        plot.deleted_at = now
    await session.flush()
    await session.refresh(farm)
    return FarmOut.from_row(farm)


# --------------------------------------------------------------------------- crop plot
async def _add_crop_plot(session: AsyncSession, farm: Farm, body: CropPlotCreate) -> CropPlot:
    await _crop(session, farm.tenant_id, body.crop_id)
    plot = CropPlot(
        id=body.id or uuid.uuid4(),
        created_at=_now(),
        tenant_id=farm.tenant_id,
        farm_id=farm.id,
        crop_id=body.crop_id,
        variety=body.variety,
        season=body.season,
        sowing_date=body.sowing_date,
        stage=body.stage,
        expected_harvest=body.expected_harvest,
        area_acres=body.area_acres,
    )
    session.add(plot)
    await session.flush()
    return plot


async def add_crop_plot(session: AsyncSession, farm: Farm, body: CropPlotCreate) -> CropPlotOut:
    plot = await _add_crop_plot(session, farm, body)
    await session.refresh(plot)
    return CropPlotOut.from_row(plot)


async def update_crop_plot(
    session: AsyncSession, plot: CropPlot, body: CropPlotUpdate
) -> CropPlotOut:
    _check_version(plot, body.version)
    changes = body.model_dump(exclude_unset=True, exclude={"version"})
    if changes.get("crop_id") is not None:
        await _crop(session, plot.tenant_id, changes["crop_id"])
    for key, value in changes.items():
        setattr(plot, key, value)
    await session.flush()
    await session.refresh(plot)
    return CropPlotOut.from_row(plot)


async def delete_crop_plot(
    session: AsyncSession, plot: CropPlot, *, expected_version: int | None = None
) -> CropPlotOut:
    _check_version(plot, expected_version)
    plot.deleted_at = _now()
    await session.flush()
    await session.refresh(plot)
    return CropPlotOut.from_row(plot)


__all__ = [
    "AREA_TOLERANCE",
    "OVERLAP_THRESHOLD",
    "WARNING_AREA_MISMATCH",
    "WARNING_FARM_OVERLAP",
    "Warnings",
    "add_consent",
    "add_crop_plot",
    "add_farm",
    "check_boundary",
    "create_farmer",
    "delete_crop_plot",
    "delete_farm",
    "farm_out",
    "farmer_detail",
    "mark_phone_verified",
    "update_crop_plot",
    "update_farm",
    "update_farmer",
    "visible_crop_plot",
    "visible_farm",
    "visible_farmer",
]
