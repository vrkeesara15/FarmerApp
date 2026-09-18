"""Typed view of the ``tenant.settings`` keys the payments, invoices and day close read.

Kept next to the code that reads them (like ``farmerapp.tenants.settings`` for the M1 / M2
keys); a missing key means the default:

====================================== =========== ==========================================
key                                    default     used by
====================================== =========== ==========================================
webhook_replay_window_s                300         SEC-023 reject webhooks older than this
day_close_variance_threshold_paise     50000       ST-006 |variance| above it flags auditors
legal_name                             tenant name ST-001 seller on the GST invoice
gstin_by_state                         placeholder ST-001 seller GSTIN per state (one GSTIN
                                                   per state registration); TODO-HUMAN: the
                                                   real GSTINs are entered by the owner
invoice_prefix                         slug upper  ST-001 first segment of the invoice number
====================================== =========== ==========================================
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import timedelta, timezone
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

#: Business days, invoice dates and financial years are Indian Standard Time.
IST = timezone(timedelta(hours=5, minutes=30), "IST")
#: Default replay window (SEC-023): a verified event older than this is rejected as stale.
DEFAULT_REPLAY_WINDOW_S = 300
#: Default ST-006 threshold: Rs 500.
DEFAULT_VARIANCE_THRESHOLD_PAISE = 50_000

#: GST state codes (first two digits of a GSTIN) for the states the tenants operate in and
#: their neighbours (place of supply on the invoice).
GST_STATE_CODES: Mapping[str, str] = {
    "Andhra Pradesh": "37",
    "Chhattisgarh": "22",
    "Goa": "30",
    "Gujarat": "24",
    "Karnataka": "29",
    "Kerala": "32",
    "Madhya Pradesh": "23",
    "Maharashtra": "27",
    "Odisha": "21",
    "Tamil Nadu": "33",
    "Telangana": "36",
}


def state_code(state: str) -> str:
    """The GST state code of ``state`` (``"00"`` when unknown: the invoice still renders)."""
    return GST_STATE_CODES.get(state, "00")


def placeholder_gstin(state: str) -> str:
    """A syntactically valid, obviously fake GSTIN for dev / demo tenants (TODO-HUMAN)."""
    return f"{state_code(state)}AAAAA0000A1Z5"


class PaymentSettings(BaseModel):
    model_config = ConfigDict(extra="ignore")

    webhook_replay_window_s: int = Field(default=DEFAULT_REPLAY_WINDOW_S, ge=30, le=86_400)
    day_close_variance_threshold_paise: int = Field(default=DEFAULT_VARIANCE_THRESHOLD_PAISE, ge=0)
    legal_name: str | None = Field(default=None, max_length=200)
    gstin_by_state: dict[str, str] = Field(default_factory=dict)
    invoice_prefix: str | None = Field(default=None, max_length=8, pattern=r"^[A-Z0-9]+$")

    def gstin_for(self, state: str) -> str:
        return self.gstin_by_state.get(state) or placeholder_gstin(state)


def payment_settings(raw: Mapping[str, Any] | None) -> PaymentSettings:
    """The payments view of a tenant's settings (``payment_settings(tenant.settings)``)."""
    return PaymentSettings.model_validate(dict(raw or {}))


__all__ = [
    "DEFAULT_REPLAY_WINDOW_S",
    "DEFAULT_VARIANCE_THRESHOLD_PAISE",
    "GST_STATE_CODES",
    "IST",
    "PaymentSettings",
    "payment_settings",
    "placeholder_gstin",
    "state_code",
]
