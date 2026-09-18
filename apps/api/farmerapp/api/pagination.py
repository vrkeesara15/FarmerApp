"""Cursor pagination (SPEC 8.3): ``?cursor=&limit=`` over a ``(created_at, id)`` keyset.

The cursor is opaque to clients: URL-safe base64 of ``{"c": <created_at iso>, "i": <id>}``
of the last item returned. Responses are ``{"items": [...], "next_cursor": str | null}``.
"""

from __future__ import annotations

import base64
import binascii
import json
import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Annotated, Any, Protocol, TypeVar

from fastapi import Depends, Query
from pydantic import BaseModel
from sqlalchemy import ColumnElement, SQLColumnExpression, literal, tuple_

from farmerapp.api.errors import AppError

DEFAULT_LIMIT = 50
MAX_LIMIT = 200


class InvalidCursorError(AppError):
    status = 400
    code = "invalid_cursor"


@dataclass(frozen=True)
class Cursor:
    created_at: datetime
    id: uuid.UUID


def encode_cursor(created_at: datetime, id: uuid.UUID) -> str:
    raw = json.dumps({"c": created_at.isoformat(), "i": str(id)}, separators=(",", ":"))
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def decode_cursor(token: str) -> Cursor:
    try:
        padded = token + "=" * (-len(token) % 4)
        data = json.loads(base64.urlsafe_b64decode(padded.encode()).decode())
        created_at = datetime.fromisoformat(data["c"])
        if created_at.tzinfo is None:
            raise ValueError("naive timestamp")
        return Cursor(created_at=created_at, id=uuid.UUID(data["i"]))
    except (ValueError, KeyError, TypeError, binascii.Error, UnicodeDecodeError) as exc:
        raise InvalidCursorError("Malformed cursor.") from exc


class HasKeyset(Protocol):
    created_at: datetime
    id: uuid.UUID


T = TypeVar("T", bound=HasKeyset)


@dataclass(frozen=True)
class PageRequest:
    cursor: Cursor | None
    limit: int

    def after(
        self, created_at: SQLColumnExpression[Any], id: SQLColumnExpression[Any]
    ) -> ColumnElement[bool] | None:
        """Keyset filter for rows strictly after the cursor (``None`` on the first page)."""
        if self.cursor is None:
            return None
        return tuple_(created_at, id) > tuple_(
            literal(self.cursor.created_at), literal(self.cursor.id)
        )

    @property
    def fetch(self) -> int:
        """Rows to fetch: one more than the page to learn whether a next page exists."""
        return self.limit + 1

    def slice(self, rows: Sequence[T]) -> tuple[list[T], str | None]:
        """Split ``fetch`` rows into the page and the cursor pointing after it."""
        items = list(rows[: self.limit])
        if len(rows) <= self.limit or not items:
            return items, None
        last = items[-1]
        return items, encode_cursor(last.created_at, last.id)


def page_request(
    cursor: Annotated[str | None, Query(description="Opaque cursor from `next_cursor`.")] = None,
    limit: Annotated[int, Query(ge=1, le=MAX_LIMIT, description="Page size.")] = DEFAULT_LIMIT,
) -> PageRequest:
    return PageRequest(cursor=decode_cursor(cursor) if cursor else None, limit=limit)


Page = Annotated[PageRequest, Depends(page_request)]


class PageOut[ItemT: BaseModel](BaseModel):
    items: list[ItemT]
    next_cursor: str | None = None


__all__ = [
    "DEFAULT_LIMIT",
    "MAX_LIMIT",
    "Cursor",
    "InvalidCursorError",
    "Page",
    "PageOut",
    "PageRequest",
    "decode_cursor",
    "encode_cursor",
    "page_request",
]
