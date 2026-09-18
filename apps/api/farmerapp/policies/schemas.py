"""``/v1/policies/location`` request / response models (FA-011 / VV-010)."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class LocationPolicyOut(BaseModel):
    version: str = Field(description="The tenant's `location_policy_version` (VV-010).")
    text_hash: str = Field(description="sha256 binding version and text; echo it on accept.")
    text: dict[str, list[str]] = Field(
        description="Four short points per language: en, te, kn, hi, mr (SPEC 13.2 A05)."
    )


class PolicyAcceptIn(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client id (sync); else server-set.")
    version: str = Field(min_length=1, max_length=32)
    text_hash: str = Field(min_length=64, max_length=64, pattern=r"^[0-9a-f]{64}$")
    device_id: str = Field(min_length=1, max_length=128)
    app_version: str = Field(min_length=1, max_length=32)
    accepted_at: datetime | None = Field(
        default=None, description="When the user tapped agree (offline first run); default now."
    )


__all__ = ["LocationPolicyOut", "PolicyAcceptIn"]
