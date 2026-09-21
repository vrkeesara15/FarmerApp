"""FM-012 wire shapes. Money is integer paise per quintal; days are IST ``YYYY-MM-DD``."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field

#: Shown next to every figure in both apps (FM-012): a mandi price is a public reference, not
#: a FarmerApp quote and not a promise by any store.
INDICATIVE_NOTE_KEY = "mandi.indicative"


class MandiQuoteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    market: str = Field(description="Mandi name as published by the source.")
    district: str
    state: str
    variety: str
    grade: str
    price_date: date = Field(description='The "as of" date of the figure (IST).')
    min_price_paise: int
    modal_price_paise: int = Field(description="The headline price per quintal, in paise.")
    max_price_paise: int
    source: str = Field(description="Dataset key: `agmarknet` or `fake`.")
    source_name: str = Field(description="Display name of the source, shown with the date.")
    source_url: str | None = None
    fetched_at: datetime


class CropPricesOut(BaseModel):
    crop_id: uuid.UUID
    crop_code: str
    crop_name: str
    crop_names: dict[str, str] = Field(
        default_factory=dict, description='Localised names, e.g. {"te": "వరి"}.'
    )
    price_date: date | None = Field(
        default=None, description='The "as of" date; null when no price is held yet.'
    )
    source_name: str | None = None
    source_url: str | None = None
    quotes: list[MandiQuoteOut] = Field(default_factory=list)


class MandiPricesOut(BaseModel):
    """``GET /v1/me/mandi-prices`` and ``GET /v1/farmers/{id}/mandi-prices``."""

    farmer_id: uuid.UUID
    district: str | None = None
    #: The newest ``price_date`` across all crops — what the app shows as the screen's "as of".
    as_of: date | None = None
    #: i18n key for the "prices are indicative" note both apps must show (FM-012).
    indicative_note_key: str = INDICATIVE_NOTE_KEY
    crops: list[CropPricesOut] = Field(default_factory=list)


__all__ = ["INDICATIVE_NOTE_KEY", "CropPricesOut", "MandiPricesOut", "MandiQuoteOut"]
