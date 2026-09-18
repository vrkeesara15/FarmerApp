"""GST tax invoice PDF (ST-001), rendered with fpdf2 (pure Python, no system fonts).

Layout follows the GST invoice particulars (rule 46): "TAX INVOICE", supplier name,
address, GSTIN and state code, invoice number and date, recipient (name, masked phone,
GSTIN when registered), place of supply with state code, per line description, HSN,
quantity, rate, taxable value, CGST / SGST (intra-state) or IGST (inter-state) rate and
amount, totals, round-off, grand total and the total in words. Core PDF fonts are Latin-1:
other scripts are replaced (names are also stored on the invoice row in full).
"""

from __future__ import annotations

from decimal import Decimal

from fpdf import FPDF
from fpdf.enums import XPos, YPos

from farmerapp.auth.providers import mask_phone
from farmerapp.invoices.gst import rate_label
from farmerapp.invoices.models import Invoice, SupplyType
from farmerapp.payments.config import IST

IST_FORMAT = "%d-%m-%Y"


def _latin1(text: str) -> str:
    return text.encode("latin-1", "replace").decode("latin-1")


def inr(paise: int) -> str:
    """``12345678`` -> ``"1,23,456.78"`` (Indian digit grouping)."""
    sign = "-" if paise < 0 else ""
    rupees, rest = divmod(abs(paise), 100)
    digits = str(rupees)
    if len(digits) > 3:
        head, tail = digits[:-3], digits[-3:]
        groups: list[str] = []
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        if head:
            groups.insert(0, head)
        digits = ",".join([*groups, tail])
    return f"{sign}{digits}.{rest:02d}"


def _qty(value: str) -> str:
    q = Decimal(value).normalize()
    return f"{q:f}"


def render_invoice_pdf(invoice: Invoice) -> bytes:
    intra = invoice.supply_type == SupplyType.INTRA
    pdf = FPDF(orientation="P", unit="mm", format="A4")
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.set_title(_latin1(f"Tax invoice {invoice.invoice_no}"))
    pdf.set_author(_latin1(invoice.seller_name))
    pdf.add_page()

    def line(text: str, *, size: float = 9, bold: bool = False, align: str = "L") -> None:
        pdf.set_font("Helvetica", "B" if bold else "", size)
        pdf.cell(0, 5, _latin1(text), new_x=XPos.LMARGIN, new_y=YPos.NEXT, align=align)

    line("TAX INVOICE", size=14, bold=True, align="C")
    pdf.ln(2)
    line(invoice.seller_name, size=11, bold=True)
    line(invoice.seller_address)
    line(f"GSTIN: {invoice.seller_gstin}")
    line(f"State: {invoice.seller_state} (Code {invoice.seller_state_code})")
    pdf.ln(2)
    line(f"Invoice No: {invoice.invoice_no}", bold=True)
    line(f"Invoice Date: {invoice.issued_at.astimezone(IST).strftime(IST_FORMAT)}")
    line(f"Place of Supply: {invoice.place_of_supply}")
    line(f"Supply: {'Intra-state (CGST + SGST)' if intra else 'Inter-state (IGST)'}")
    pdf.ln(2)
    line("Bill To:", bold=True)
    line(invoice.buyer_name)
    if invoice.buyer_phone:
        line(f"Phone: {mask_phone(invoice.buyer_phone)}")
    if invoice.buyer_gstin:
        line(f"GSTIN: {invoice.buyer_gstin}")
    line(f"State: {invoice.buyer_state}")
    pdf.ln(3)

    if intra:
        headers = ["#", "Description", "HSN", "Qty", "Rate", "Taxable", "CGST", "SGST", "Total"]
        widths = [7, 55, 16, 14, 18, 20, 20, 20, 20]
    else:
        headers = ["#", "Description", "HSN", "Qty", "Rate", "Taxable", "IGST", "Total"]
        widths = [7, 65, 16, 14, 20, 22, 26, 20]
    pdf.set_font("Helvetica", "B", 8)
    for header, width in zip(headers, widths, strict=True):
        pdf.cell(width, 6, header, border=1, align="C")
    pdf.ln()
    pdf.set_font("Helvetica", "", 8)
    for item in invoice.lines:
        cells = [
            str(item["sl"]),
            str(item["description"])[:40],
            str(item["hsn"]),
            f"{_qty(str(item['qty']))} {item.get('unit', '')}".strip(),
            inr(int(item["unit_price_paise"])),
            inr(int(item["taxable_paise"])),
        ]
        if intra:
            cells += [
                f"{rate_label(int(item['cgst_rate_bp']))} {inr(int(item['cgst_paise']))}",
                f"{rate_label(int(item['sgst_rate_bp']))} {inr(int(item['sgst_paise']))}",
            ]
        else:
            cells.append(f"{rate_label(int(item['igst_rate_bp']))} {inr(int(item['igst_paise']))}")
        cells.append(inr(int(item["total_paise"])))
        for i, (text, width) in enumerate(zip(cells, widths, strict=True)):
            pdf.cell(width, 6, _latin1(text), border=1, align="L" if i == 1 else "R")
        pdf.ln()
    pdf.ln(2)

    def total(label: str, paise: int, *, bold: bool = False) -> None:
        pdf.set_font("Helvetica", "B" if bold else "", 9)
        pdf.cell(150, 5, label, align="R")
        pdf.cell(40, 5, inr(paise), align="R", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

    total("Taxable Value (Rs)", invoice.taxable_paise)
    if intra:
        total("CGST (Rs)", invoice.cgst_paise)
        total("SGST (Rs)", invoice.sgst_paise)
    else:
        total("IGST (Rs)", invoice.igst_paise)
    total("Round Off (Rs)", invoice.round_off_paise)
    total("Grand Total (Rs)", invoice.total_paise, bold=True)
    pdf.ln(2)
    pdf.set_font("Helvetica", "", 9)
    pdf.multi_cell(0, 5, _latin1(f"Amount in words: {invoice.amount_in_words}"))
    pdf.ln(4)
    line("This is a computer-generated invoice.", size=7)
    return bytes(pdf.output())


__all__ = ["inr", "render_invoice_pdf"]
