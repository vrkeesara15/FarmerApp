"""Request/response models for ``/v1/users`` (minimal WC-011 slice)."""

from __future__ import annotations

import uuid

from pydantic import BaseModel, ConfigDict, Field, model_validator

from farmerapp.api.pagination import PageOut
from farmerapp.auth.models import UserRole, UserStatus
from farmerapp.auth.schemas import UserOut


class UserUpdate(BaseModel):
    """PATCH body: only the fields present are changed; ``null`` clears store/cluster."""

    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=200)
    role: UserRole | None = None
    status: UserStatus | None = None
    store_id: uuid.UUID | None = None
    cluster_id: uuid.UUID | None = None

    @model_validator(mode="after")
    def _at_least_one_field(self) -> UserUpdate:
        if not self.model_fields_set:
            raise ValueError("at least one field must be provided")
        return self


UserPage = PageOut[UserOut]

__all__ = ["UserOut", "UserPage", "UserUpdate"]
