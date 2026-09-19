"""Targets and incentives (WC-009; migration 0031_growth).

* ``sales_target`` — the monthly target of one officer or one store (``subject_type``
  ``officer`` / ``store``, ``month`` = the first day of the month): verified visits, new
  farmers, sales and collections in paise, own-brand share in basis points. A NULL metric
  has no target. Unique per tenant, month and subject.
* ``incentive_rule_set`` — the tenant's declarative incentive rules, **versioned**: every
  save is a new ``version`` (a JSON document validated by
  ``farmerapp.incentives.rules.RuleDefinition``); one set is ``active`` at a time
  (activating one retires the previous). Stored rules are never edited in place, so a frozen
  payout can always name the exact rules it was computed with.
* ``incentive_payout`` — the frozen result of the monthly close for one officer: the rule
  set and version used, the metrics, the per-component lines, gross, clawback and the
  payable amount. Unique per tenant, officer and month; the close job never recomputes a
  frozen month.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns


class TargetSubject(StrEnum):
    OFFICER = "officer"
    STORE = "store"


class RuleSetStatus(StrEnum):
    DRAFT = "draft"
    ACTIVE = "active"
    RETIRED = "retired"


class SalesTarget(Base, BaseColumns):
    __tablename__ = "sales_target"
    __table_args__ = (
        UniqueConstraint("tenant_id", "month", "subject_type", "subject_id"),
        CheckConstraint(f"subject_type IN ({sql_in(TargetSubject)})", name="subject_type"),
        CheckConstraint("extract(day FROM month) = 1", name="month"),
        CheckConstraint(
            "(visits_verified IS NULL OR visits_verified >= 0) AND "
            "(new_farmers IS NULL OR new_farmers >= 0) AND "
            "(sales_paise IS NULL OR sales_paise >= 0) AND "
            "(collections_paise IS NULL OR collections_paise >= 0) AND "
            "(own_brand_share_bp IS NULL OR own_brand_share_bp BETWEEN 0 AND 10000)",
            name="values",
        ),
        Index("ix_sales_target_subject", "tenant_id", "subject_type", "subject_id", "month"),
    )

    month: Mapped[date] = mapped_column(Date, nullable=False)
    subject_type: Mapped[str] = mapped_column(String(8), nullable=False)
    subject_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    visits_verified: Mapped[int | None] = mapped_column(Integer, nullable=True)
    new_farmers: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sales_paise: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    collections_paise: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    own_brand_share_bp: Mapped[int | None] = mapped_column(Integer, nullable=True)
    set_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )


class IncentiveRuleSet(Base, BaseColumns):
    __tablename__ = "incentive_rule_set"
    __table_args__ = (
        UniqueConstraint("tenant_id", "version_no"),
        CheckConstraint(f"status IN ({sql_in(RuleSetStatus)})", name="status"),
        CheckConstraint("version_no > 0", name="version_no"),
        Index(
            "uq_incentive_rule_set_active",
            "tenant_id",
            unique=True,
            postgresql_where=text("status = 'active' AND deleted_at IS NULL"),
        ),
    )

    name: Mapped[str] = mapped_column(String(120), nullable=False)
    #: The rule set number (1, 2, ...). ``version`` is the optimistic-locking column.
    rule_version: Mapped[int] = mapped_column("version_no", Integer, nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default=RuleSetStatus.DRAFT.value
    )
    definition: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    activated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    activated_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)


class IncentivePayout(Base, BaseColumns):
    __tablename__ = "incentive_payout"
    __table_args__ = (
        UniqueConstraint("tenant_id", "officer_id", "month"),
        CheckConstraint("extract(day FROM month) = 1", name="month"),
        CheckConstraint("gross_paise >= 0 AND clawback_paise >= 0", name="amounts"),
        Index("ix_incentive_payout_month", "tenant_id", "month"),
    )

    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    month: Mapped[date] = mapped_column(Date, nullable=False)
    rule_set_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("incentive_rule_set.id", ondelete="SET NULL"), nullable=True
    )
    rule_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    eligible: Mapped[bool] = mapped_column(nullable=False, default=True)
    metrics: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    lines: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list)
    gross_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    clawback_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    closed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    closed_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)


__all__ = [
    "IncentivePayout",
    "IncentiveRuleSet",
    "RuleSetStatus",
    "SalesTarget",
    "TargetSubject",
]
