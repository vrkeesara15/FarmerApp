"""WC-014 tenant provisioning: one call makes a tenant a new officer can work in.

Acceptance (SPEC 2.5): *a new tenant is usable in under 30 minutes*. The way to hit that is
to leave nothing manual between "create the tenant" and "register the first farmer", so
``provision_tenant`` does, in one transaction:

1. the ``tenant`` row — name, slug, plan (plus any per-tenant limit overrides), status
   ``active``;
2. its **settings**, validated through ``TenantSettings`` so the row starts with every
   documented default already resolved (languages, default language, branding, geofence,
   quiet hours, …) rather than an empty ``{}`` that each reader has to fall back from;
3. **placeholders to hang data on**: one cluster and one store at the region's default point.
   A store is what a farmer, an officer and a price list all need a foreign key to, so a
   tenant without one is not usable; the operator renames and re-points it afterwards;
4. the **reference data**: the pilot crops (FA-004 names in five languages), the pest and
   disease master, the crop-calendar task templates (FM-007), the VA-F05 crop calendar and
   the VA-F04 service area derived from the store;
5. the **rule set with the tenant's overrides**: the validated ``rules/*.yaml`` set applies to
   every tenant as it stands; ``disabled_rules`` in the request writes the ``enabled = false``
   ``rule_tenant_override`` rows (VA-006) that make this tenant's set differ;
6. the **first ``tenant_admin``**, with a phone that logs in through the ordinary FA-001 OTP
   flow. No password, no console seat to provision, nothing to e-mail: the follow-up
   ``POST /v1/admin/tenants/{id}/invite`` sends them their first code;
7. the **usage counters** (WC-014), so the plan limits are enforced from the first request.

The registry row (``platform_tenant``) is written last, under the platform tenant's binding.
Everything before it is written inside ``tenant_scope(new tenant)``: the provisioning code has
no special database rights, it is the ordinary app role writing rows of the tenant it is bound
to, which is why RLS still covers every one of them.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.templates import seed_crop_task_templates
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.catalog.crops import PILOT_CROPS, Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import tenant_scope
from farmerapp.flags.models import OverrideSource, RuleTenantOverride
from farmerapp.jobs.seed_catalog import PROBLEMS
from farmerapp.logging import get_logger
from farmerapp.platform_admin.errors import TenantSlugTakenError
from farmerapp.platform_admin.models import (
    PLATFORM_TENANT_ID,
    PLATFORM_TENANT_NAME,
    PLATFORM_TENANT_SLUG,
    PlatformTenant,
    TenantStatus,
)
from farmerapp.platform_admin.plans import DEFAULT_PLAN, Metric, plan_by_name
from farmerapp.platform_admin.usage import record
from farmerapp.rules.loader import get_rule_set
from farmerapp.rules.reference import StorePoint, seed_crop_calendar, service_area_setting
from farmerapp.tenants.models import Cluster, Store
from farmerapp.tenants.settings import Branding, TenantSettings

#: NF-008 launch languages, in the order the SPEC lists them.
LANGUAGES: tuple[str, ...] = ("en", "te", "kn", "hi", "mr")

log = get_logger("farmerapp.platform_admin.provisioning")

#: Regions we may place a tenant in (NF-011 data residency: India only).
REGIONS: tuple[str, ...] = ("asia-south1", "asia-south2")
DEFAULT_REGION = "asia-south1"

#: Where a placeholder store is put until the operator moves it: the region's capital.
REGION_POINT: dict[str, tuple[float, float, str, str]] = {
    # region -> (lat, lon, district, state)
    "asia-south1": (17.3850, 78.4867, "Hyderabad", "Telangana"),
    "asia-south2": (28.6139, 77.2090, "New Delhi", "Delhi"),
}


@dataclass(frozen=True)
class TenantSpec:
    """What a platform admin asks for when creating a tenant."""

    name: str
    slug: str
    plan: str = DEFAULT_PLAN
    region: str = DEFAULT_REGION
    primary_contact_name: str = "Tenant admin"
    primary_contact_phone: str = ""
    languages: tuple[str, ...] = ()
    default_language: str = "en"
    branding: dict[str, Any] = field(default_factory=dict)
    plan_limits: dict[str, Any] = field(default_factory=dict)
    disabled_rules: tuple[str, ...] = ()
    notes: str | None = None


@dataclass(frozen=True)
class ProvisionResult:
    tenant_id: uuid.UUID
    slug: str
    admin_user_id: uuid.UUID
    store_id: uuid.UUID
    cluster_id: uuid.UUID
    created: dict[str, int]
    elapsed_ms: int

    def as_json(self) -> dict[str, Any]:
        return {
            "store_id": str(self.store_id),
            "cluster_id": str(self.cluster_id),
            "created": dict(self.created),
            "elapsed_ms": self.elapsed_ms,
        }


# --------------------------------------------------------------------------- platform tenant
async def ensure_platform_tenant(session: AsyncSession) -> Tenant:
    """The tenant that owns the registry. Idempotent; safe to call on every boot and seed."""
    async with tenant_scope(session, PLATFORM_TENANT_ID):
        tenant = await session.get(Tenant, PLATFORM_TENANT_ID)
        if tenant is None:
            tenant = Tenant(
                id=PLATFORM_TENANT_ID,
                tenant_id=PLATFORM_TENANT_ID,
                name=PLATFORM_TENANT_NAME,
                slug=PLATFORM_TENANT_SLUG,
                plan="unlimited",
                status=TenantStatus.ACTIVE,
                settings=TenantSettings().model_dump(mode="json"),
                branding={},
                plan_limits={},
            )
            session.add(tenant)
            await session.flush()
        return tenant


async def ensure_platform_admin(
    session: AsyncSession, *, phone: str, name: str = "Platform admin"
) -> User:
    """A ``platform_admin`` account in the platform tenant (idempotent by phone)."""
    await ensure_platform_tenant(session)
    async with tenant_scope(session, PLATFORM_TENANT_ID):
        from farmerapp.pii.lookup import phone_match

        existing = (
            await session.execute(
                select(User).where(User.tenant_id == PLATFORM_TENANT_ID, phone_match(User, phone))
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing
        user = User(
            id=uuid.uuid4(),
            tenant_id=PLATFORM_TENANT_ID,
            phone=phone,
            name=name,
            role=UserRole.PLATFORM_ADMIN,
            language="en",
            status=UserStatus.ACTIVE,
        )
        session.add(user)
        await session.flush()
        return user


# --------------------------------------------------------------------------- provisioning
def _default_settings(spec: TenantSpec) -> dict[str, Any]:
    languages = tuple(spec.languages) or LANGUAGES
    default_language = spec.default_language if spec.default_language in languages else languages[0]
    branding = Branding.model_validate(spec.branding or {})
    settings = TenantSettings(
        languages_enabled=list(languages),
        default_language=default_language,
        branding=branding,
        legal_name=spec.name,
        invoice_prefix=spec.slug.upper()[:8] or "TENANT",
    )
    return settings.model_dump(mode="json")


async def _seed_reference(session: AsyncSession, tenant_id: uuid.UUID) -> dict[str, int]:
    """Crops, pest / disease master and calendar templates for a brand-new tenant."""
    crops: dict[str, Crop] = {}
    for code, name, names, duration in PILOT_CROPS:
        row = Crop(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            code=code,
            name=name,
            names=dict(names),
            duration_days=duration,
        )
        session.add(row)
        crops[code] = row
    await session.flush()

    problems = 0
    for spec in PROBLEMS:
        crop: Crop | None = crops.get(spec.crop) if spec.crop else None
        if spec.crop and crop is None:
            continue
        session.add(
            PestOrDisease(
                id=uuid.uuid4(),
                tenant_id=tenant_id,
                code=spec.code,
                name=spec.name,
                names=dict(spec.names),
                type=spec.type,
                crop_id=crop.id if crop is not None else None,
                scientific_name=spec.scientific_name,
                symptoms=spec.symptoms,
            )
        )
        problems += 1
    await session.flush()
    templates = await seed_crop_task_templates(session, tenant_id)
    return {"crops": len(crops), "pest_master": problems, "calendar_templates": templates}


async def _apply_rule_overrides(
    session: AsyncSession, tenant_id: uuid.UUID, rule_ids: Sequence[str], now: datetime
) -> int:
    """VA-006 ``enabled = false`` rows for the rules this tenant does not run."""
    if not rule_ids:
        return 0
    known = set(get_rule_set().rules)
    written = 0
    for rule_id in rule_ids:
        if rule_id not in known:
            continue
        session.add(
            RuleTenantOverride(
                id=uuid.uuid4(),
                tenant_id=tenant_id,
                rule_id=rule_id,
                enabled=False,
                source=OverrideSource.ADMIN,
                reason="Disabled at provisioning (WC-014).",
                set_at=now,
            )
        )
        written += 1
    await session.flush()
    return written


async def provision_tenant(
    session: AsyncSession,
    spec: TenantSpec,
    *,
    now: datetime | None = None,
) -> ProvisionResult:
    """Create and fill a tenant. The caller's session must be bound to the platform tenant."""
    moment = now or datetime.now(UTC)
    started = datetime.now(UTC)
    plan = plan_by_name(spec.plan)
    # The slug is unique across the whole database, but the caller's session is bound to the
    # platform tenant and RLS hides other tenants' rows, so the registry is what we can read
    # (and what covers every tenant WC-014 created). The unique index is still the authority:
    # the insert below runs in a savepoint and turns its violation into the same 409, which
    # also catches a collision with a tenant that predates the registry.
    taken = await session.scalar(
        select(PlatformTenant.id).where(
            PlatformTenant.tenant_id == PLATFORM_TENANT_ID,
            PlatformTenant.slug == spec.slug,
            PlatformTenant.deleted_at.is_(None),
        )
    )
    if taken is not None:
        raise TenantSlugTakenError(f"The slug {spec.slug!r} is already in use.")

    tenant_id = uuid.uuid4()
    lat, lon, district, state = REGION_POINT.get(spec.region, REGION_POINT[DEFAULT_REGION])
    created: dict[str, int] = {}

    async with tenant_scope(session, tenant_id):
        tenant = Tenant(
            id=tenant_id,
            tenant_id=tenant_id,
            name=spec.name,
            slug=spec.slug,
            plan=plan.name,
            status=TenantStatus.ACTIVE,
            plan_limits=dict(spec.plan_limits),
            branding=dict(spec.branding or {}),
            settings=_default_settings(spec),
        )
        try:
            async with session.begin_nested():
                session.add(tenant)
                await session.flush()
        except IntegrityError as exc:
            raise TenantSlugTakenError(f"The slug {spec.slug!r} is already in use.") from exc

        cluster = Cluster(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            name="Default cluster",
            district=district,
            state=state,
        )
        session.add(cluster)
        await session.flush()
        from farmerapp.db.geo import point_wkt

        store = Store(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            code=(spec.slug.upper().replace("-", "")[:8] or "HQ") + "01",
            name=f"{spec.name} HQ",
            cluster_id=cluster.id,
            district=district,
            state=state,
            location=point_wkt(lon, lat),
        )
        session.add(store)
        await session.flush()
        created |= {"clusters": 1, "stores": 1}

        created |= await _seed_reference(session, tenant_id)
        await seed_crop_calendar(session, tenant_id, state=state)
        settings = dict(tenant.settings)
        settings["service_area"] = service_area_setting(
            [StorePoint(store.code, district, state, lon, lat)]
        )
        tenant.settings = settings
        created["rule_overrides"] = await _apply_rule_overrides(
            session, tenant_id, spec.disabled_rules, moment
        )

        admin = User(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            phone=spec.primary_contact_phone,
            name=spec.primary_contact_name,
            role=UserRole.TENANT_ADMIN,
            language=spec.default_language,
            status=UserStatus.ACTIVE,
        )
        session.add(admin)
        await session.flush()
        created["users"] = 1

        # WC-014: start the counters so the plan is enforced from the first request.
        await record(session, tenant_id, Metric.STORES, 1, when=moment)
        await record(session, tenant_id, Metric.OFFICERS, 0, when=moment)

    registry = PlatformTenant(
        id=uuid.uuid4(),
        tenant_id=PLATFORM_TENANT_ID,
        subject_tenant_id=tenant_id,
        slug=spec.slug,
        name=spec.name,
        plan=plan.name,
        status=TenantStatus.ACTIVE,
        region=spec.region,
        primary_contact_user_id=admin.id,
        primary_contact_name=spec.primary_contact_name,
        plan_limits=dict(spec.plan_limits),
        provisioned_at=moment,
        notes=spec.notes,
    )
    session.add(registry)
    await session.flush()

    elapsed_ms = int((datetime.now(UTC) - started).total_seconds() * 1000)
    result = ProvisionResult(
        tenant_id=tenant_id,
        slug=spec.slug,
        admin_user_id=admin.id,
        store_id=store.id,
        cluster_id=cluster.id,
        created=created,
        elapsed_ms=elapsed_ms,
    )
    registry.provisioned = result.as_json()
    await session.flush()
    log.info(
        "tenant_provisioned",
        tenant_id=str(tenant_id),
        slug=spec.slug,
        plan=plan.name,
        region=spec.region,
        created=created,
        elapsed_ms=elapsed_ms,
    )
    return result


__all__ = [
    "DEFAULT_REGION",
    "REGIONS",
    "ProvisionResult",
    "TenantSpec",
    "ensure_platform_admin",
    "ensure_platform_tenant",
    "provision_tenant",
]
