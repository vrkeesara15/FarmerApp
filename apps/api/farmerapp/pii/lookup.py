"""Lookups by phone through the searchable hash (SEC-026).

``phone_match(Model, phone)`` is the one way to find a ``user`` / ``farmer`` by phone (OTP
login, duplicate checks, VA-F01 staff phones, POS farmer lookup, directory search). During
the transition (rows written before Alembic 0025 and not yet backfilled) a row without a
hash still matches on its legacy plain column; the contract step removes that branch.
"""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from sqlalchemy import ColumnElement, and_, or_

from farmerapp.pii.crypto import phone_hash


def phone_match(model: Any, phone: str) -> ColumnElement[bool]:
    return or_(
        model.phone_hash == phone_hash(phone),
        and_(model.phone_hash.is_(None), model.phone_plain == phone),
    )


def phone_in(model: Any, phones: Iterable[str]) -> ColumnElement[bool]:
    values = sorted(set(phones))
    return or_(
        model.phone_hash.in_([phone_hash(p) for p in values]),
        and_(model.phone_hash.is_(None), model.phone_plain.in_(values)),
    )


__all__ = ["phone_in", "phone_match"]
