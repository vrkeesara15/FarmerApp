"""GST computation for a tax invoice (ST-001) — pure functions, integer paise.

* **Supply type.** Intra-state when the buyer's state is the store's state (a walk-in buyer
  is treated as local): CGST + SGST, each at half the rate. Inter-state: IGST at the full
  rate.
* **Per line.** Taxable value = ``qty x unit price`` (pre-tax, half-up to the paisa); each
  tax component = taxable x its rate, half-up to the paisa, computed separately (so CGST and
  SGST are always equal on a line, as the GST format expects).
* **Round-off.** The invoice total is rounded half-up to the rupee; the difference is the
  round-off line (``-50 .. +50`` paise).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from farmerapp.catalog.models import BASIS_POINTS
from farmerapp.invoices.models import SupplyType
from farmerapp.orders.models import line_total_paise


def half_up(value: Decimal) -> int:
    return int(value.quantize(Decimal(1), rounding=ROUND_HALF_UP))


def tax_on(taxable_paise: int, rate_bp: int, *, halves: bool = False) -> int:
    """Tax on a taxable value at ``rate_bp`` basis points (half the rate for CGST / SGST)."""
    divisor = BASIS_POINTS * (2 if halves else 1)
    return half_up(Decimal(taxable_paise) * rate_bp / divisor)


def supply_type(seller_state: str, buyer_state: str | None) -> SupplyType:
    if buyer_state is None or buyer_state.strip().casefold() == seller_state.strip().casefold():
        return SupplyType.INTRA
    return SupplyType.INTER


@dataclass(frozen=True)
class LineInput:
    sku_id: uuid.UUID
    description: str
    hsn: str | None
    qty: Decimal
    unit: str
    unit_price_paise: int
    gst_rate_bp: int


@dataclass(frozen=True)
class InvoiceLine:
    sl: int
    sku_id: uuid.UUID
    description: str
    hsn: str
    qty: Decimal
    unit: str
    unit_price_paise: int
    taxable_paise: int
    gst_rate_bp: int
    cgst_paise: int
    sgst_paise: int
    igst_paise: int
    inter: bool = False

    @property
    def tax_paise(self) -> int:
        return self.cgst_paise + self.sgst_paise + self.igst_paise

    @property
    def total_paise(self) -> int:
        return self.taxable_paise + self.tax_paise

    @property
    def half_rate_bp(self) -> int:
        return 0 if self.inter else self.gst_rate_bp // 2  # GST slabs are even in bp

    def as_json(self) -> dict[str, object]:
        half = self.half_rate_bp
        return {
            "sl": self.sl,
            "sku_id": str(self.sku_id),
            "description": self.description,
            "hsn": self.hsn,
            "qty": str(self.qty),
            "unit": self.unit,
            "unit_price_paise": self.unit_price_paise,
            "taxable_paise": self.taxable_paise,
            "gst_rate_bp": self.gst_rate_bp,
            "cgst_rate_bp": half,
            "cgst_paise": self.cgst_paise,
            "sgst_rate_bp": half,
            "sgst_paise": self.sgst_paise,
            "igst_rate_bp": self.gst_rate_bp if self.inter else 0,
            "igst_paise": self.igst_paise,
            "total_paise": self.total_paise,
        }


@dataclass(frozen=True)
class InvoiceTotals:
    supply_type: SupplyType
    lines: tuple[InvoiceLine, ...]
    taxable_paise: int
    cgst_paise: int
    sgst_paise: int
    igst_paise: int
    round_off_paise: int
    total_paise: int

    @property
    def tax_paise(self) -> int:
        return self.cgst_paise + self.sgst_paise + self.igst_paise

    @property
    def exact_total_paise(self) -> int:
        """Total before the round-off (what the order stores: subtotal + tax)."""
        return self.taxable_paise + self.tax_paise


def compute_invoice(lines: Sequence[LineInput], kind: SupplyType) -> InvoiceTotals:
    out: list[InvoiceLine] = []
    for i, line in enumerate(lines, start=1):
        taxable = line_total_paise(line.qty, line.unit_price_paise)
        if kind == SupplyType.INTRA:
            half = tax_on(taxable, line.gst_rate_bp, halves=True)
            cgst, sgst, igst = half, half, 0
        else:
            cgst, sgst, igst = 0, 0, tax_on(taxable, line.gst_rate_bp)
        out.append(
            InvoiceLine(
                sl=i,
                sku_id=line.sku_id,
                description=line.description,
                hsn=line.hsn or "",
                qty=line.qty,
                unit=line.unit,
                unit_price_paise=line.unit_price_paise,
                taxable_paise=taxable,
                gst_rate_bp=line.gst_rate_bp,
                cgst_paise=cgst,
                sgst_paise=sgst,
                igst_paise=igst,
                inter=kind == SupplyType.INTER,
            )
        )
    taxable = sum(x.taxable_paise for x in out)
    cgst = sum(x.cgst_paise for x in out)
    sgst = sum(x.sgst_paise for x in out)
    igst = sum(x.igst_paise for x in out)
    exact = taxable + cgst + sgst + igst
    total = half_up(Decimal(exact) / 100) * 100
    return InvoiceTotals(
        supply_type=kind,
        lines=tuple(out),
        taxable_paise=taxable,
        cgst_paise=cgst,
        sgst_paise=sgst,
        igst_paise=igst,
        round_off_paise=total - exact,
        total_paise=total,
    )


def rate_label(rate_bp: int) -> str:
    """``900`` -> ``"9%"``, ``250`` -> ``"2.5%"``."""
    value = Decimal(rate_bp) / 100
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return f"{text}%"


__all__ = [
    "InvoiceLine",
    "InvoiceTotals",
    "LineInput",
    "compute_invoice",
    "half_up",
    "rate_label",
    "supply_type",
    "tax_on",
]
