"""Golden-fixture records of the M7 rules (``seed_m7``, called by ``harness.seed``).

.. code-block:: yaml

    seed:
      tenant_settings: {service_area: {...}, discount_policy_max_bps: 1000, ...}  # merged
      crop_calendar: telangana              # the seeded windows, or a list of
                                            # {state?, district?, crop, season, start, end}
      crop_plots: [{ref, farm, crop, season, sown: "2026-06-20" | -30d}]
      consents:   [{farmer, purpose?, granted?: -10d, withdrawn?: -2d}]
      farmer_logins: [{farmer, at}]         # a farmer app login (user + refresh token)
      orders: [{ref, placed_by?, farmer?, at, subtotal, discount?, status?, cancelled?: -1d}]
      khata:  [{ref, farmer, type: debit|credit, amount, at, due?: -100d}]
      day_closes: [{ref, closed_by?, at, expected, counted, status?}]
      segment_members: [{farmer, segment, campaign?}]          # SegmentMembershipPort fake
      travel_claims: [{ref, officer?, day: -1d, km, type?: fuel, sessions?: [d1]}]  # port fake
      track_gaps: [{ref, duty, officer?, start: -30h, end: -26h, reason?, reason_at?}]  # VV-006
      land_cover: [{farm, class: water|built_up|road|cropland}]         # LandCoverPort fake

Crops (the six pilot crops) are created on first use. Amounts are paise. ``day`` / ``due``
/ ``sown`` accept the relative syntax (the IST date of that instant) or an ISO date.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import RefreshToken, User, UserRole
from farmerapp.catalog.crops import PILOT_CROPS, Crop
from farmerapp.db.models import Tenant
from farmerapp.duty.models import TrackGap, gap_id
from farmerapp.farmers.models import ConsentChannel, ConsentRecord, ConsentSubject, CropPlot, Farmer
from farmerapp.khata.models import EntryRef, EntryType, KhataEntry
from farmerapp.location.models import DutySession
from farmerapp.orders.models import Order, OrderChannel, OrderStatus, OrderStatusEvent
from farmerapp.payments.models import DayClose, DayCloseStatus
from farmerapp.rules.checks.common import IST
from farmerapp.rules.models import CropCalendar
from farmerapp.rules.ports import LandCover, SegmentMember, TravelClaim
from farmerapp.rules.reference import TELANGANA_CROP_CALENDAR, seed_crop_calendar
from tests.rules.harness import BaseWorld, when


def day_of(value: Any, now: Any) -> date:
    if isinstance(value, date) and not hasattr(value, "tzinfo"):
        return value
    text = str(value)
    if len(text) == 10 and text[4] == "-" and not text.startswith("-"):
        return date.fromisoformat(text)
    return when(value, now).astimezone(IST).date()


async def _crop(session: AsyncSession, world: BaseWorld, code: str) -> uuid.UUID:
    key = f"crop:{code}"
    if key in world.refs:
        return world.refs[key]
    spec = next(c for c in PILOT_CROPS if c[0] == code)
    crop = Crop(
        tenant_id=world.tenant_id, code=code, name=spec[1], names=spec[2], duration_days=spec[3]
    )
    session.add(crop)
    await session.flush()
    world.refs[key] = crop.id
    return crop.id


async def seed_m7(
    session: AsyncSession, world: BaseWorld, records: dict[str, Any], now: Any
) -> None:
    if records.get("tenant_settings"):
        tenant = await session.get_one(Tenant, world.tenant_id)
        tenant.settings = {**(tenant.settings or {}), **records["tenant_settings"]}
        await session.flush()
    calendar = records.get("crop_calendar") or []
    specs: list[Any] = [calendar] if isinstance(calendar, str) else list(calendar)
    for spec in specs:
        if spec == "telangana":
            await seed_crop_calendar(session, world.tenant_id, windows=TELANGANA_CROP_CALENDAR)
        else:
            session.add(
                CropCalendar(
                    tenant_id=world.tenant_id,
                    state=spec.get("state", "Telangana"),
                    district=spec.get("district"),
                    crop_code=spec["crop"],
                    season=spec["season"],
                    sow_start=spec["start"],
                    sow_end=spec["end"],
                )
            )
        await session.flush()
    for spec in records.get("crop_plots") or []:
        crop_id = await _crop(session, world, spec["crop"])
        plot = CropPlot(
            tenant_id=world.tenant_id,
            farm_id=world.refs[spec["farm"]],
            crop_id=crop_id,
            season=spec["season"],
            sowing_date=day_of(spec["sown"], now),
        )
        session.add(plot)
        await session.flush()
        world.refs[spec["ref"]] = plot.id
    for spec in records.get("consents") or []:
        granted = spec.get("granted")
        withdrawn = spec.get("withdrawn")
        at = when(withdrawn or granted, now)
        session.add(
            ConsentRecord(
                tenant_id=world.tenant_id,
                created_at=at,
                subject_type=ConsentSubject.FARMER.value,
                subject_id=world.refs[spec["farmer"]],
                purpose=spec.get("purpose", "marketing"),
                version="2026-09-v1",
                granted_at=at if withdrawn is None else None,
                withdrawn_at=at if withdrawn is not None else None,
                channel=ConsentChannel.OFFICER.value,
            )
        )
        await session.flush()
    for spec in records.get("farmer_logins") or []:
        farmer = await session.get_one(Farmer, world.refs[spec["farmer"]])
        at = when(spec.get("at"), now)
        if farmer.user_id is None:
            user = User(
                tenant_id=world.tenant_id,
                phone=farmer.phone,
                name=farmer.name,
                role=UserRole.FARMER.value,
            )
            session.add(user)
            await session.flush()
            farmer.user_id = user.id
        session.add(
            RefreshToken(
                tenant_id=world.tenant_id,
                created_at=at,
                user_id=farmer.user_id,
                family_id=uuid.uuid4(),
                token_hash=hashlib.sha256(uuid.uuid4().bytes).hexdigest(),
                expires_at=at + timedelta(days=30),
            )
        )
        await session.flush()
    for spec in records.get("orders") or []:
        await _order(session, world, spec, now)
    for spec in records.get("khata") or []:
        entry = KhataEntry(
            tenant_id=world.tenant_id,
            created_at=when(spec.get("at"), now),
            farmer_id=world.refs[spec["farmer"]],
            store_id=world.refs[spec.get("store", "s1")],
            type=EntryType(spec["type"]).value,
            amount_paise=int(spec["amount"]),
            due_date=day_of(spec["due"], now) if spec.get("due") else None,
            ref_type=(EntryRef.ORDER if spec["type"] == "debit" else EntryRef.PAYMENT).value,
        )
        session.add(entry)
        await session.flush()
        world.refs[spec["ref"]] = entry.id
    for spec in records.get("day_closes") or []:
        at = when(spec.get("at"), now)
        expected, counted = int(spec["expected"]), int(spec["counted"])
        close = DayClose(
            tenant_id=world.tenant_id,
            store_id=world.refs[spec.get("store", "s1")],
            business_date=at.astimezone(IST).date(),
            cash_expected_paise=expected,
            cash_counted_paise=counted,
            variance_paise=counted - expected,
            closed_by=world.refs[spec.get("closed_by", "store_manager")],
            closed_at=at,
            status=DayCloseStatus(spec.get("status", "closed")).value,
        )
        session.add(close)
        await session.flush()
        world.refs[spec["ref"]] = close.id
    for spec in records.get("segment_members") or []:
        world.segments.rows.append(
            SegmentMember(
                tenant_id=world.tenant_id,
                farmer_id=world.refs[spec["farmer"]],
                segment_id=str(spec["segment"]),
                campaign_id=spec.get("campaign"),
            )
        )
    for spec in records.get("travel_claims") or []:
        claim_id = uuid.uuid4()
        world.refs[spec["ref"]] = claim_id
        world.travel_claims.rows.append(
            TravelClaim(
                tenant_id=world.tenant_id,
                id=claim_id,
                officer_id=world.refs[spec.get("officer", "officer")],
                day=day_of(spec["day"], now),
                claimed_km=Decimal(str(spec["km"])),
                submitted_at=when(spec.get("at"), now),
                duty_session_ids=tuple(world.refs[r] for r in spec.get("sessions") or []),
                claim_type=str(spec.get("type", "fuel")),
            )
        )
    for spec in records.get("track_gaps") or []:
        duty = await session.get_one(DutySession, world.refs[spec["duty"]])
        start, end = when(spec["start"], now), when(spec["end"], now)
        gap = TrackGap(
            id=gap_id(duty.id, start),
            tenant_id=world.tenant_id,
            duty_session_id=duty.id,
            officer_id=duty.officer_id,
            start_at=start,
            end_at=end,
            duration_s=int((end - start).total_seconds()),
            reason=spec.get("reason"),
            note=spec.get("note"),
            reason_at=when(spec["reason_at"], now) if spec.get("reason_at") else None,
        )
        session.add(gap)
        await session.flush()
        world.refs[spec["ref"]] = gap.id
    for spec in records.get("land_cover") or []:
        world.land_cover.by_farm[world.refs[spec["farm"]]] = LandCover(spec["class"])


async def _order(session: AsyncSession, world: BaseWorld, spec: dict[str, Any], now: Any) -> None:
    at = when(spec.get("at"), now)
    subtotal = int(spec["subtotal"])
    discount = int(spec.get("discount", 0))
    cancelled = spec.get("cancelled")
    status = OrderStatus.CANCELLED if cancelled else OrderStatus(spec.get("status", "handed_over"))
    seller = world.refs[spec.get("placed_by", "officer")]
    farmer = spec.get("farmer")
    order = Order(
        tenant_id=world.tenant_id,
        created_at=at,
        farmer_id=world.refs[farmer] if farmer else None,
        store_id=world.refs[spec.get("store", "s1")],
        channel=OrderChannel(spec.get("channel", "officer")).value,
        status=status.value,
        subtotal_paise=subtotal,
        discount_paise=discount,
        tax_paise=0,
        total_paise=subtotal - discount,
        placed_by=seller,
        placed_at=at,
    )
    session.add(order)
    await session.flush()
    world.refs[spec["ref"]] = order.id
    session.add(
        OrderStatusEvent(
            tenant_id=world.tenant_id,
            created_at=at,
            order_id=order.id,
            from_status=None,
            to_status=OrderStatus.PLACED.value,
            actor_id=seller,
        )
    )
    if cancelled:
        session.add(
            OrderStatusEvent(
                tenant_id=world.tenant_id,
                created_at=when(cancelled, now),
                order_id=order.id,
                from_status=OrderStatus.PLACED.value,
                to_status=OrderStatus.CANCELLED.value,
                actor_id=seller,
            )
        )
    await session.flush()


__all__ = ["day_of", "seed_m7"]
