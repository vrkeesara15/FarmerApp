"""AN-016 wire shapes."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class AskIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    question: str = Field(min_length=3, max_length=500)


class AskViewColumnOut(BaseModel):
    name: str
    description: str


class AskViewOut(BaseModel):
    name: str
    grain: str
    description: str
    columns: list[AskViewColumnOut] = Field(default_factory=list)


class AskViewsOut(BaseModel):
    """``GET /v1/analytics/ask/views`` — what the assistant can answer from."""

    views: list[AskViewOut] = Field(default_factory=list)
    enabled: bool


class AskOut(BaseModel):
    """``POST /v1/analytics/ask``.

    ``sql`` is **generated and read-only** — the console labels it exactly that way. It is
    returned even when the query failed to run, so the reader can see what was attempted.
    """

    answered: bool
    question: str
    answer: str | None = Field(
        default=None, description="Plain-language answer; null when the question failed."
    )
    reason: str | None = Field(
        default=None, description="Why it could not be answered (refusal or validation reason)."
    )
    message_key: str | None = Field(
        default=None, description='i18n key of the "I could not answer that" headline.'
    )
    sql: str | None = Field(
        default=None, description="The generated read-only SELECT, after validation."
    )
    views: list[str] = Field(default_factory=list, description="Authorised views the query read.")
    columns: list[str] = Field(default_factory=list)
    rows: list[dict[str, Any]] = Field(default_factory=list)
    row_count: int = 0
    truncated: bool = Field(
        default=False, description="True when the row limit cut the answer short."
    )
    scope: str = Field(default="", description="What the caller may see, in words.")
    model: str | None = None
    elapsed_ms: int = 0


__all__ = ["AskIn", "AskOut", "AskViewColumnOut", "AskViewOut", "AskViewsOut"]
