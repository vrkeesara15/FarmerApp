"""GST maths, amounts in words and invoice numbers (ST-001) — pure functions."""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal

import pytest

from farmerapp.invoices.gst import (
    LineInput,
    compute_invoice,
    rate_label,
    supply_type,
    tax_on,
)
from farmerapp.invoices.models import SupplyType
from farmerapp.invoices.numbering import financial_year, format_invoice_no
from farmerapp.invoices.pdf import inr
from farmerapp.invoices.words import amount_in_words, number_in_words


def _line(qty: str, unit_paise: int, rate_bp: int, hsn: str = "3808") -> LineInput:
    return LineInput(
        sku_id=uuid.uuid4(),
        description="Item",
        hsn=hsn,
        qty=Decimal(qty),
        unit="pc",
        unit_price_paise=unit_paise,
        gst_rate_bp=rate_bp,
    )


def test_supply_type() -> None:
    assert supply_type("Telangana", "telangana ") == SupplyType.INTRA
    assert supply_type("Telangana", None) == SupplyType.INTRA  # walk-in
    assert supply_type("Telangana", "Karnataka") == SupplyType.INTER


def test_intra_state_splits_cgst_and_sgst_half_each() -> None:
    totals = compute_invoice(
        [_line("2", 45_000, 1800), _line("1", 120_000, 500, "3105")], SupplyType.INTRA
    )
    first, second = totals.lines
    assert first.taxable_paise == 90_000
    assert (first.cgst_paise, first.sgst_paise, first.igst_paise) == (8_100, 8_100, 0)
    assert (second.cgst_paise, second.sgst_paise, second.igst_paise) == (3_000, 3_000, 0)
    assert totals.taxable_paise == 210_000
    assert (totals.cgst_paise, totals.sgst_paise, totals.igst_paise) == (11_100, 11_100, 0)
    assert totals.total_paise == 232_200 and totals.round_off_paise == 0
    as_json = first.as_json()
    assert as_json["cgst_rate_bp"] == as_json["sgst_rate_bp"] == 900
    assert as_json["igst_rate_bp"] == 0 and as_json["hsn"] == "3808"


def test_inter_state_charges_igst_at_the_full_rate() -> None:
    totals = compute_invoice([_line("2", 45_000, 1800)], SupplyType.INTER)
    (line,) = totals.lines
    assert (line.cgst_paise, line.sgst_paise, line.igst_paise) == (0, 0, 16_200)
    assert line.as_json()["igst_rate_bp"] == 1800 and line.as_json()["cgst_rate_bp"] == 0
    assert totals.tax_paise == 16_200 and totals.total_paise == 106_200


def test_rounding_to_the_paisa_and_the_rupee() -> None:
    # 3 x 11.11 = 33.33 taxable; 2.5 % of 3333 paise = 83.325 -> 83 (half-up at .5 only)
    totals = compute_invoice([_line("3", 1_111, 500)], SupplyType.INTRA)
    (line,) = totals.lines
    assert line.taxable_paise == 3_333
    assert line.cgst_paise == line.sgst_paise == 83
    assert totals.exact_total_paise == 3_499
    assert totals.total_paise == 3_500 and totals.round_off_paise == 1
    # 0.5 kg x 1.01 = 0.505 -> 1 paisa (half-up), tax 18 % inter: 0.18 -> 0
    small = compute_invoice([_line("0.5", 101, 1800)], SupplyType.INTER)
    assert small.lines[0].taxable_paise == 51
    assert small.lines[0].igst_paise == 9  # 51 x 0.18 = 9.18
    assert small.total_paise == 100 and small.round_off_paise == 40
    # half a rupee rounds up; 49 paise rounds down
    down = compute_invoice([_line("1", 10_049, 0)], SupplyType.INTRA)
    assert (down.total_paise, down.round_off_paise) == (10_000, -49)
    up = compute_invoice([_line("1", 10_050, 0)], SupplyType.INTRA)
    assert (up.total_paise, up.round_off_paise) == (10_100, 50)
    assert tax_on(1, 1800, halves=True) == 0 and tax_on(5, 1800, halves=True) == 0
    assert tax_on(100, 1800) == 18


def test_nil_rated_seed_has_no_tax() -> None:
    totals = compute_invoice([_line("4", 25_000, 0, "1209")], SupplyType.INTRA)
    assert totals.tax_paise == 0 and totals.total_paise == 100_000


@pytest.mark.parametrize(
    ("paise", "words"),
    [
        (0, "Rupees Zero Only"),
        (1, "Rupees Zero and One Paise Only"),
        (100, "Rupees One Only"),
        (2_150, "Rupees Twenty-One and Fifty Paise Only"),
        (100_000, "Rupees One Thousand Only"),
        (10_000_000, "Rupees One Lakh Only"),
        (
            12_345_678,
            "Rupees One Lakh Twenty-Three Thousand Four Hundred Fifty-Six and Seventy-Eight "
            "Paise Only",
        ),
        (1_000_000_000, "Rupees One Crore Only"),
        (
            1_234_567_890_123,
            "Rupees One Thousand Two Hundred Thirty-Four Crore Fifty-Six Lakh Seventy-Eight "
            "Thousand Nine Hundred One and Twenty-Three Paise Only",
        ),
        (-500, "Minus Rupees Five Only"),
    ],
)
def test_amount_in_words_indian_system(paise: int, words: str) -> None:
    assert amount_in_words(paise) == words


def test_number_in_words_rejects_negatives() -> None:
    assert number_in_words(19) == "Nineteen" and number_in_words(90) == "Ninety"
    with pytest.raises(ValueError, match="negative"):
        number_in_words(-1)


def test_financial_year_and_number_format() -> None:
    assert financial_year(date(2026, 9, 18)) == "2026-27"
    assert financial_year(date(2027, 3, 31)) == "2026-27"
    assert financial_year(date(2027, 4, 1)) == "2027-28"
    assert financial_year(date(2099, 4, 1)) == "2099-00"
    assert format_invoice_no("FCC", "KND", "2026-27", 123) == "FCC/KND/2026-27/000123"


def test_labels_and_indian_grouping() -> None:
    assert rate_label(900) == "9%" and rate_label(250) == "2.5%" and rate_label(0) == "0%"
    assert inr(12_345_678) == "1,23,456.78"
    assert inr(99) == "0.99" and inr(-150) == "-1.50" and inr(100_000_00) == "1,00,000.00"
