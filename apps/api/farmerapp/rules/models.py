"""Reference data the M7 rules read (migration 0029).

* ``crop_calendar`` — VA-F05: the sowing window of a crop in a season, per state and
  optionally per district (``district`` NULL = state-wide; a district row wins over the
  state row). ``sow_start`` / ``sow_end`` are ``MM-DD``; a window may wrap the new year
  (rabi paddy ``11-01`` .. ``01-31``). Seeded for the six pilot crops in Telangana by
  ``farmerapp.rules.reference`` (TODO-HUMAN: agronomist review of the windows).
"""

from __future__ import annotations

from sqlalchemy import CheckConstraint, Index, String, text
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns

_MMDD = "^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$"


class CropCalendar(Base, BaseColumns):
    __tablename__ = "crop_calendar"
    __table_args__ = (
        CheckConstraint("season IN ('kharif', 'rabi', 'zaid')", name="season"),
        CheckConstraint(f"sow_start ~ '{_MMDD}' AND sow_end ~ '{_MMDD}'", name="mmdd"),
        Index(
            "uq_crop_calendar_window",
            "tenant_id",
            "state",
            text("coalesce(district, '')"),
            "crop_code",
            "season",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )

    state: Mapped[str] = mapped_column(String(80), nullable=False)
    district: Mapped[str | None] = mapped_column(String(80), nullable=True)
    crop_code: Mapped[str] = mapped_column(String(32), nullable=False)
    season: Mapped[str] = mapped_column(String(8), nullable=False)
    sow_start: Mapped[str] = mapped_column(String(5), nullable=False)
    sow_end: Mapped[str] = mapped_column(String(5), nullable=False)
    source: Mapped[str | None] = mapped_column(String(200), nullable=True)


__all__ = ["CropCalendar"]
