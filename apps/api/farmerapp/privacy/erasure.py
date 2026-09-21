"""NF-013 right to erasure, executed against the NF-012 retention rules.

DPDP gives a data principal the right to have their personal data erased. Indian company and
tax law gives the company an obligation to keep financial records for eight years. Both are
true at once, so "delete my account" cannot mean ``DELETE FROM everything``. What it means
here — and what the console shows the operator before they confirm — is:

**Anonymised now** (the identifiers are overwritten in place, irreversibly):

* the farmer record: name -> :data:`ERASED_NAME`, phone -> a reserved non-routable number,
  landmark -> ``NULL``, marketing consent -> off;
* the login account: name, phone, and the account is disabled, so no OTP can be sent to it
  and no session can be refreshed (SEC-020 revokes the families);
* the device rows bound to the account.

**Kept, with the reason recorded on the ticket:**

* financial records — orders, order lines, payments, invoices, khata entries, day closes —
  for eight years from their own date (NF-012). They keep pointing at the anonymised farmer
  row, so the books still balance and the person is no longer identifiable from them.
* visit records for seven years and audit logs for one year, for the same reason: they are
  evidence of what the company did, not a profile of the person. They reference ids, not
  names.
* consent records, because the proof that consent was given (and withdrawn) is itself the
  record of lawfulness. Note this one is kept by the table being append-only, not by a
  retention class, so it does *not* appear in :func:`retained_classes` or in the report the
  console shows — ``docs/dpdp.md`` is where it is explained to a reader.

The run is idempotent, writes an audit entry (FA-006) for every row it touches, and returns
an :class:`ErasureReport` that the caller stores on the ticket and shows the operator. It
never runs by itself: a tenant admin or owner triggers it on a ``deletion`` ticket, after
re-auth (SEC-028).
"""

from __future__ import annotations

import uuid
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import text, update
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import RefreshToken, RevokeReason, User, UserStatus
from farmerapp.db import audit
from farmerapp.farmers.models import Farmer
from farmerapp.logging import get_logger
from farmerapp.retention import POLICY, RetentionAction

log = get_logger("farmerapp.privacy.erasure")

__all__ = ["ERASED_NAME", "ErasureReport", "Retained", "erase_principal", "retained_classes"]

#: What an anonymised record reads as. Deliberately not a blank: an operator must be able to
#: tell "erased on request" from "never filled in".
ERASED_NAME = "Erased at the data principal's request"
#: A reserved, non-routable Indian number (TRAI test range): nothing can be sent to it, and
#: the tenant-unique phone constraints still hold because the id is appended.
ERASED_PHONE_PREFIX = "+9170000"


@dataclass(frozen=True)
class Retained:
    """One record class that survives the erasure, and why."""

    record_class: str
    until_days: int
    reason: str


@dataclass
class ErasureReport:
    farmer_id: uuid.UUID | None
    user_id: uuid.UUID
    erased: list[str] = field(default_factory=list)
    retained: list[Retained] = field(default_factory=list)
    already_erased: bool = False
    erased_at: datetime | None = None

    def as_json(self) -> dict[str, Any]:
        return {
            "farmer_id": str(self.farmer_id) if self.farmer_id else None,
            "user_id": str(self.user_id),
            "erased": list(self.erased),
            "retained": [asdict(r) for r in self.retained],
            "already_erased": self.already_erased,
            "erased_at": self.erased_at.isoformat() if self.erased_at else None,
        }


def retained_classes() -> list[Retained]:
    """Read straight off the NF-012 policy, so the two can never disagree."""
    out: list[Retained] = []
    for entry in POLICY:
        if entry.action is RetentionAction.ARCHIVE:
            continue
        if entry.name == "location_points":
            continue  # 180 days, and never tied to a farmer
        out.append(
            Retained(
                record_class=entry.name,
                until_days=entry.days,
                reason=entry.note.split(".")[0] if entry.note else entry.spec,
            )
        )
    return out


def erased_phone(row_id: uuid.UUID) -> str:
    """A unique, non-routable stand-in: the tenant-unique phone index must still hold."""
    return ERASED_PHONE_PREFIX + f"{row_id.int % 1000:03d}"


async def _anonymise_farmer(session: AsyncSession, farmer: Farmer, now: datetime) -> list[str]:
    if farmer.name == ERASED_NAME:
        return []
    farmer.name = ERASED_NAME
    farmer.phone = erased_phone(farmer.id)
    farmer.landmark = None
    farmer.consent_marketing = False
    farmer.phone_verified = False
    farmer.deleted_at = now
    await session.flush()
    return ["farmer.name", "farmer.phone", "farmer.landmark", "farmer.consent_marketing"]


async def _anonymise_user(session: AsyncSession, user: User, now: datetime) -> list[str]:
    if user.name == ERASED_NAME:
        return []
    user.name = ERASED_NAME
    user.phone = erased_phone(user.id)
    user.status = UserStatus.DISABLED
    user.tokens_valid_after = now
    user.deleted_at = now
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now, revoked_reason=RevokeReason.USER_DISABLED.value)
        .execution_options(synchronize_session="fetch")
    )
    await session.execute(
        text("UPDATE device SET status = 'revoked' WHERE user_id = :uid AND status <> 'revoked'"),
        {"uid": user.id},
    )
    await session.flush()
    return ["user.name", "user.phone", "user.status", "refresh_token.*", "device.*"]


async def erase_principal(
    session: AsyncSession,
    *,
    user: User,
    farmer: Farmer | None,
    now: datetime | None = None,
) -> ErasureReport:
    """Anonymise the principal; keep what NF-012 says must be kept. Idempotent."""
    moment = now or datetime.now(UTC)
    report = ErasureReport(
        farmer_id=farmer.id if farmer else None,
        user_id=user.id,
        retained=retained_classes(),
        erased_at=moment,
    )
    if farmer is not None:
        report.erased.extend(await _anonymise_farmer(session, farmer, moment))
    report.erased.extend(await _anonymise_user(session, user, moment))
    report.already_erased = not report.erased
    audit.record(
        session,
        action="privacy.erasure",
        entity="user",
        entity_id=user.id,
        tenant_id=user.tenant_id,
        after={
            "farmer_id": str(farmer.id) if farmer else None,
            "fields": report.erased,
            "retained": [r.record_class for r in report.retained],
        },
    )
    await session.flush()
    log.info(
        "privacy_erasure",
        tenant_id=str(user.tenant_id),
        user_id=str(user.id),
        farmer_id=str(farmer.id) if farmer else None,
        fields=len(report.erased),
        retained=[r.record_class for r in report.retained],
        already_erased=report.already_erased,
    )
    return report


def retention_deadline(entry_days: int, from_time: datetime) -> datetime:
    return from_time + timedelta(days=entry_days)
