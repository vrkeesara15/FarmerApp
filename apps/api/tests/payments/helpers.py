"""Shared helpers for the FA-021 / SEC-023 / ST-001 / ST-002 / ST-006 tests.

``PayWorld`` = the seeded world (SMALL) plus: the store manager's store, a farmer of that
store, fake payment services installed on the app (``FakePaymentProvider``, ``FakeLedger``),
and builders for orders, khata debits, uploaded blobs and signed webhooks.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.auth.providers import FakeProvider
from farmerapp.db.audit import Actor
from farmerapp.farmers.models import Farmer
from farmerapp.khata.models import EntryRef, EntryType, KhataEntry
from farmerapp.orders.models import Order, OrderChannel, OrderStatus
from farmerapp.payments.providers import (
    FakePaymentProvider,
    hmac_sha256_hex,
    razorpay_envelope,
)
from farmerapp.payments.service import PaymentServices
from farmerapp.settings import get_settings
from farmerapp.tenants.models import Store, Village
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import Bearer, World

WEBHOOK_KEY = "unit-test-webhook-hmac-key"


@dataclass(frozen=True)
class Decision:
    allowed: bool
    approval_request_id: uuid.UUID | None = None
    shortfall_paise: int = 0


@dataclass
class FakeLedger:
    """``LedgerPort`` fake: records calls; ``post_credit`` appends a real credit entry so
    balances move exactly as with the orders branch's ``post_credit``."""

    decision: Decision = field(default_factory=lambda: Decision(True))
    checks: list[dict[str, Any]] = field(default_factory=list)
    credits: list[dict[str, Any]] = field(default_factory=list)

    async def check_and_reserve_credit(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        farmer_id: uuid.UUID,
        store_id: uuid.UUID,
        amount_paise: int,
        order_id: uuid.UUID | None,
        actor: Actor,
    ) -> Decision:
        self.checks.append(
            {
                "tenant_id": tenant_id,
                "farmer_id": farmer_id,
                "store_id": store_id,
                "amount_paise": amount_paise,
                "order_id": order_id,
                "actor": actor,
            }
        )
        return self.decision

    async def post_credit(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        farmer_id: uuid.UUID,
        store_id: uuid.UUID,
        amount_paise: int,
        ref_type: str,
        ref_id: uuid.UUID,
        actor: Actor,
    ) -> KhataEntry:
        entry = KhataEntry(
            tenant_id=tenant_id,
            created_at=datetime.now(UTC),
            farmer_id=farmer_id,
            store_id=store_id,
            type=EntryType.CREDIT,
            amount_paise=amount_paise,
            ref_type=EntryRef(ref_type),
            ref_id=ref_id,
            created_by=actor.actor_id,
        )
        session.add(entry)
        await session.flush()
        self.credits.append({"amount_paise": amount_paise, "ref_id": ref_id, "actor": actor})
        return entry


@dataclass
class PayWorld:
    world: World
    app: FastAPI
    session: AsyncSession
    bearer: Bearer
    store: Store
    other_store: Store | None
    farmer: Farmer  # a farmer of ``store`` (village -> store)
    provider: FakePaymentProvider
    ledger: FakeLedger
    services: PaymentServices

    @property
    def tenant_id(self) -> uuid.UUID:
        return self.world.a.tenant.id

    def user(self, role: str | UserRole) -> User:
        return self.world.a.user(role)

    def headers(self, role: str | UserRole) -> dict[str, str]:
        return self.bearer(self.user(role))

    @property
    def messages(self) -> FakeProvider:
        sms = self.app.state.auth.sms
        assert isinstance(sms, FakeProvider)
        return sms

    @property
    def blobs(self) -> BlobStore:
        blobs: BlobStore = self.app.state.blobs
        return blobs

    async def order(
        self,
        total_paise: int = 118_000,
        *,
        farmer: Farmer | bool | None = True,
        store: Store | None = None,
        status: OrderStatus = OrderStatus.PLACED,
        placed_by: User | None = None,
        channel: OrderChannel = OrderChannel.OFFICER,
    ) -> Order:
        chosen = self.farmer if farmer is True else (None if farmer is False else farmer)
        tax = total_paise * 18 // 118
        order = Order(
            tenant_id=self.tenant_id,
            farmer_id=chosen.id if isinstance(chosen, Farmer) else None,
            store_id=(store or self.store).id,
            channel=channel.value,
            status=status.value,
            subtotal_paise=total_paise - tax,
            discount_paise=0,
            tax_paise=tax,
            total_paise=total_paise,
            placed_by=(placed_by or self.user(UserRole.FIELD_OFFICER)).id,
            placed_at=datetime.now(UTC),
        )
        self.session.add(order)
        await self.session.flush()
        return order

    async def debit(
        self, amount_paise: int, *, farmer: Farmer | None = None, store: Store | None = None
    ) -> KhataEntry:
        entry = KhataEntry(
            tenant_id=self.tenant_id,
            created_at=datetime.now(UTC),
            farmer_id=(farmer or self.farmer).id,
            store_id=(store or self.store).id,
            type=EntryType.DEBIT,
            amount_paise=amount_paise,
            ref_type=EntryRef.ADJUSTMENT,
            note="test debit",
        )
        self.session.add(entry)
        await self.session.flush()
        return entry

    async def blob(self, purpose: str = "receipt", data: bytes | None = None) -> str:
        data = data or uuid.uuid4().bytes
        sha = hashlib.sha256(data).hexdigest()
        return await self.blobs.put(
            f"{self.tenant_id}/{purpose}/{sha}", data, content_type="image/jpeg"
        )

    def webhook(
        self,
        event: str,
        *,
        payment: dict[str, Any] | None = None,
        created_at: datetime | None = None,
        event_id: str | None = None,
        key: str | None = None,
        **extra: Any,
    ) -> tuple[bytes, dict[str, str]]:
        body = razorpay_envelope(
            event, payment=payment, created_at=created_at or datetime.now(UTC), **extra
        )
        return body, {
            "Content-Type": "application/json",
            "X-Razorpay-Signature": hmac_sha256_hex(key or self.provider.webhook_secret, body),
            "X-Razorpay-Event-Id": event_id or f"evt_{uuid.uuid4().hex[:14]}",
        }

    def captured(
        self, payment_id: uuid.UUID | str, amount_paise: int, **notes: str
    ) -> dict[str, Any]:
        return {
            "id": f"pay_{uuid.uuid4().hex[:14]}",
            "entity": "payment",
            "amount": amount_paise,
            "status": "captured",
            "method": "upi",
            "notes": {"tenant_id": str(self.tenant_id), "payment_id": str(payment_id), **notes},
        }


async def farmer_of_store(session: AsyncSession, store_id: uuid.UUID) -> Farmer:
    farmer = (
        await session.execute(
            select(Farmer)
            .join(Village, Village.id == Farmer.village_id)
            .where(Village.store_id == store_id, Farmer.deleted_at.is_(None))
            .order_by(Farmer.created_at, Farmer.id)
            .limit(1)
        )
    ).scalar_one()
    return farmer


async def make_pay_world(
    app: FastAPI, session: AsyncSession, world: World, bearer: Bearer
) -> PayWorld:
    assert world.a.store_id is not None
    store = await session.get_one(Store, world.a.store_id)
    other = (
        await session.execute(
            select(Store).where(Store.id != store.id).order_by(Store.code).limit(1)
        )
    ).scalar_one_or_none()
    provider = FakePaymentProvider(webhook_secret=WEBHOOK_KEY)
    ledger = FakeLedger()
    services = PaymentServices(settings=get_settings(), provider=provider, ledger=ledger)
    app.state.payments = services
    return PayWorld(
        world=world,
        app=app,
        session=session,
        bearer=bearer,
        store=store,
        other_store=other,
        farmer=await farmer_of_store(session, store.id),
        provider=provider,
        ledger=ledger,
        services=services,
    )


@asynccontextmanager
async def same_session(session: AsyncSession) -> AsyncIterator[AsyncSession]:
    """Session provider for the worker handler in tests: the test's own transaction."""
    yield session


def as_json(body: bytes) -> dict[str, Any]:
    parsed: dict[str, Any] = json.loads(body)
    return parsed


__all__ = [
    "WEBHOOK_KEY",
    "Decision",
    "FakeLedger",
    "PayWorld",
    "as_json",
    "farmer_of_store",
    "make_pay_world",
    "same_session",
]
