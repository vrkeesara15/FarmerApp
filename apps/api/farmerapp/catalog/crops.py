"""Crop master (``crop``): the six pilot crops now, tenant-extensible later (WC-005).

Referenced by ``crop_plot.crop_id`` (M1), ``label_claim.crop_id`` and the diagnosis corpus
(M3 / M6). ``names`` holds the display name per language (``{"te": "వరి", "hi": "धान"}``)
so the apps never hard-code crop strings (FA-004); ``name`` is the English fallback.
"""

from __future__ import annotations

from typing import Any

from sqlalchemy import Boolean, Integer, String, UniqueConstraint, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class Crop(Base, BaseColumns):
    __tablename__ = "crop"
    __table_args__ = (UniqueConstraint("tenant_id", "code"),)

    code: Mapped[str] = mapped_column(String(32), nullable=False)  # paddy, cotton, ...
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    names: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb"), default=dict
    )
    duration_days: Mapped[int | None] = mapped_column(Integer, nullable=True)  # sowing→harvest
    active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("true"), default=True
    )


#: SPEC §0.3 pilot crops (open question resolved by assumption; see docs/progress.md).
PILOT_CROPS: tuple[tuple[str, str, dict[str, str], int], ...] = (
    ("paddy", "Paddy", {"te": "వరి", "hi": "धान", "kn": "ಭತ್ತ", "mr": "भात"}, 130),
    ("cotton", "Cotton", {"te": "పత్తి", "hi": "कपास", "kn": "ಹತ್ತಿ", "mr": "कापूस"}, 170),
    ("chilli", "Chilli", {"te": "మిరప", "hi": "मिर्च", "kn": "ಮೆಣಸಿನಕಾಯಿ", "mr": "मिरची"}, 180),
    ("maize", "Maize", {"te": "మొక్కజొన్న", "hi": "मक्का", "kn": "ಮೆಕ್ಕೆಜೋಳ", "mr": "मका"}, 100),
    ("tomato", "Tomato", {"te": "టమాటా", "hi": "टमाटर", "kn": "ಟೊಮೇಟೊ", "mr": "टोमॅटो"}, 90),
    ("groundnut", "Groundnut", {"te": "వేరుశనగ", "hi": "मूंगफली", "kn": "ಕಡಲೆಕಾಯಿ", "mr": "भुईमूग"}, 110),
)

__all__ = ["PILOT_CROPS", "Crop"]
