"""``payment`` create op of ``POST /v1/sync`` (FA-021: officer offline capture).

A field officer collects cash (with the receipt photo) or puts a sale on credit while
offline; the outbox replays the op later. The op's ``entity_id`` becomes the payment id, so
a replay of an op that already applied is a ``conflict`` carrying the server row (server
wins for money, FA-025). Payload = the ``POST /v1/payments`` body. UPI QR and payment links
need the provider while the farmer is in front of the officer: offline they are rejected
with ``requires_network``. Amounts are recomputed server-side exactly as for the REST call
(a stale client amount is ``amount_mismatch``).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError
from farmerapp.auth.models import User
from farmerapp.auth.providers import SmsProvider, WhatsAppProvider
from farmerapp.payments.models import PROVIDER_MODES, Payment, PaymentMode
from farmerapp.payments.schemas import PaymentCreate, PaymentOut
from farmerapp.payments.service import (
    Messaging,
    PaymentServices,
    create_payment,
    visible_payment,
)
from farmerapp.uploads.blobstore import BlobStore


class RequiresNetworkError(AppError):
    status = 422
    code = "requires_network"


class PaymentSyncUnavailableError(AppError):
    status = 503
    code = "unsupported_action"


@dataclass(frozen=True)
class Applied:
    out: PaymentOut
    conflict: bool


async def create(
    session: AsyncSession,
    actor: User,
    entity_id: uuid.UUID,
    payload: dict[str, Any],
    *,
    services: PaymentServices | None,
    sms: SmsProvider | None,
    whatsapp: WhatsAppProvider | None,
    blobs: BlobStore | None,
    now: datetime,
) -> Applied:
    if services is None or sms is None or whatsapp is None or blobs is None:
        raise PaymentSyncUnavailableError("Payment sync ops need the payment services.")
    existing = await session.get(Payment, entity_id)
    if existing is not None:
        row = await visible_payment(session, actor, entity_id)
        return Applied(PaymentOut.model_validate(row), conflict=True)
    body = PaymentCreate.model_validate(payload)
    if PaymentMode(body.mode) in PROVIDER_MODES:
        raise RequiresNetworkError("UPI QR and payment links need the network: collect online.")
    await create_payment(
        session,
        actor,
        body,
        services=services,
        messaging=Messaging(sms=sms, whatsapp=whatsapp),
        blobs=blobs,
        now=now,
        payment_id=entity_id,
    )
    row = await session.get_one(Payment, entity_id)
    return Applied(PaymentOut.model_validate(row), conflict=False)


__all__ = ["Applied", "PaymentSyncUnavailableError", "RequiresNetworkError", "create"]
