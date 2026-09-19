"""ST-008 daily accounting export per store: Tally CSV, Tally voucher XML, Zoho Books CSV.

For one store and one IST business day:

* **Sales vouchers** — the GST invoices issued that day (``invoice.issued_at``): the party
  (buyer) is debited the invoice total; per HSN and GST rate the sales ledger
  (``"<sales_ledger_prefix> @ 18%"``) is credited the taxable value; per rate the output tax
  ledgers (``"Output CGST @ 9%"`` / ``"Output SGST @ 9%"`` or ``"Output IGST @ 18%"``) are
  credited the tax — the **GST breakup**; the round-off goes to the round-off ledger.
* **Credit notes** — invoices whose order was cancelled that day (the ``order_status_event``
  to ``cancelled``): the exact reverse of the sale, numbered ``CN-<invoice no>``.
* **Receipts** — payments received that day (paid, reconciled, or cash pending the day
  close; not khata credit): the cash / UPI / card ledger is debited, the party credited.

Amounts are rupees with two decimals (``1234.50``), dates ``dd-mm-yyyy`` (Tally) /
``yyyy-mm-dd`` (Zoho). Every voucher balances (debits = credits), which the golden-file test
checks. Column sets are fixed (``TALLY_COLUMNS``, ``ZOHO_COLUMNS``): the accountant validates
the first file against the books before the daily export is relied on (ST-008 acceptance,
human gate). Ledger names come from ``TenantSettings.accounting``.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import AsyncIterator, Sequence
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any
from xml.sax.saxutils import escape  # nosec B406 - escaping only, no XML parsing

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.scope import visible_store_filters
from farmerapp.farmers.models import Farmer
from farmerapp.invoices.models import Invoice, SupplyType
from farmerapp.orders.models import Order, OrderStatus, OrderStatusEvent
from farmerapp.payments.config import IST
from farmerapp.payments.day_close import day_bounds
from farmerapp.payments.models import RECEIVED_STATUSES, Payment, PaymentMode
from farmerapp.tenants.models import Store
from farmerapp.tenants.settings import AccountingSettings, get_tenant_settings

R = UserRole
ACCOUNTING_ROLES = frozenset(
    {
        R.OWNER,
        R.DIRECTOR,
        R.TENANT_ADMIN,
        R.AUDITOR,
        R.ACCOUNTANT,
        R.CLUSTER_HEAD,
        R.STORE_MANAGER,
    }
)

TALLY_COLUMNS = (
    "Voucher Date",
    "Voucher Type",
    "Voucher Number",
    "Reference",
    "Party Ledger",
    "Party GSTIN",
    "Place of Supply",
    "Ledger",
    "Dr/Cr",
    "Amount",
    "HSN",
    "GST Rate",
    "Taxable Value",
    "Narration",
)
ZOHO_COLUMNS = (
    "Invoice Date",
    "Invoice Number",
    "Invoice Status",
    "Customer Name",
    "GST Treatment",
    "GST Identification Number (GSTIN)",
    "Place of Supply",
    "Item Name",
    "HSN/SAC",
    "Quantity",
    "Usage unit",
    "Item Price",
    "Item Tax",
    "Item Tax %",
    "Item Tax Type",
    "Adjustment",
    "Adjustment Description",
    "Currency Code",
    "Notes",
)


def rupees(paise: int) -> str:
    sign = "-" if paise < 0 else ""
    whole, rest = divmod(abs(paise), 100)
    return f"{sign}{whole}.{rest:02d}"


def rate_text(bp: int) -> str:
    """``1800`` -> ``"18"``, ``250`` -> ``"2.5"`` (percent)."""
    value = bp / 100
    return f"{value:g}"


@dataclass(frozen=True)
class Receipt:
    payment: Payment
    party: str


@dataclass
class AccountingDay:
    store: Store
    day: date
    invoices: list[Invoice] = field(default_factory=list)
    credit_notes: list[Invoice] = field(default_factory=list)
    receipts: list[Receipt] = field(default_factory=list)


async def visible_store(session: AsyncSession, actor: User, store_id: uuid.UUID) -> Store:
    store = (
        await session.execute(
            select(Store).where(
                Store.id == store_id, Store.deleted_at.is_(None), *visible_store_filters(actor)
            )
        )
    ).scalar_one_or_none()
    if store is None:
        raise NotFoundError("Store not found.")
    return store


async def load_day(session: AsyncSession, store: Store, day: date) -> AccountingDay:
    start, end = day_bounds(day)
    tid = store.tenant_id
    invoices = (
        await session.execute(
            select(Invoice)
            .where(
                Invoice.tenant_id == tid,
                Invoice.store_id == store.id,
                Invoice.deleted_at.is_(None),
                Invoice.issued_at >= start,
                Invoice.issued_at < end,
            )
            .order_by(Invoice.issued_at, Invoice.seq)
        )
    ).scalars()
    cancelled_today = select(OrderStatusEvent.order_id).where(
        OrderStatusEvent.tenant_id == tid,
        OrderStatusEvent.to_status == OrderStatus.CANCELLED.value,
        OrderStatusEvent.created_at >= start,
        OrderStatusEvent.created_at < end,
    )
    credit = (
        await session.execute(
            select(Invoice)
            .join(Order, Order.id == Invoice.order_id)
            .where(
                Invoice.tenant_id == tid,
                Invoice.store_id == store.id,
                Invoice.deleted_at.is_(None),
                Order.status == OrderStatus.CANCELLED.value,
                Order.id.in_(cancelled_today),
            )
            .order_by(Invoice.issued_at, Invoice.seq)
        )
    ).scalars()
    received_at = func.coalesce(Payment.paid_at, Payment.created_at)
    payments = (
        await session.execute(
            select(Payment, Farmer.name)
            .outerjoin(Farmer, Farmer.id == Payment.farmer_id)
            .where(
                Payment.tenant_id == tid,
                Payment.store_id == store.id,
                Payment.deleted_at.is_(None),
                Payment.mode != PaymentMode.CREDIT.value,
                Payment.status.in_([s.value for s in RECEIVED_STATUSES]),
                received_at >= start,
                received_at < end,
            )
            .order_by(received_at, Payment.id)
        )
    ).tuples()
    settings = await get_tenant_settings(session, tid)
    return AccountingDay(
        store=store,
        day=day,
        invoices=list(invoices),
        credit_notes=list(credit),
        receipts=[Receipt(p, name or settings.accounting.walk_in_party) for p, name in payments],
    )


# --------------------------------------------------------------------------- entries
@dataclass(frozen=True)
class Entry:
    ledger: str
    debit: bool
    amount_paise: int
    hsn: str | None = None
    rate_bp: int | None = None
    taxable_paise: int | None = None


@dataclass(frozen=True)
class Voucher:
    kind: str  # Sales | Credit Note | Receipt
    number: str
    when: datetime
    reference: str
    party: str
    party_gstin: str | None
    place_of_supply: str | None
    entries: tuple[Entry, ...]
    narration: str

    def balanced(self) -> bool:
        dr = sum(e.amount_paise for e in self.entries if e.debit)
        cr = sum(e.amount_paise for e in self.entries if not e.debit)
        return dr == cr


def _sale_entries(inv: Invoice, acc: AccountingSettings, *, reverse: bool) -> list[Entry]:
    """Party Dr total; sales per (HSN, rate) Cr; output tax per rate Cr; round-off."""
    credit = reverse  # a sale credits income (debit=False); a credit note debits it
    entries = [Entry(inv.buyer_name, not reverse, inv.total_paise)]
    by_hsn: dict[tuple[str, int], int] = defaultdict(int)
    tax: dict[tuple[str, int], int] = defaultdict(int)
    for line in inv.lines or []:
        rate = int(line.get("gst_rate_bp") or 0)
        by_hsn[(str(line.get("hsn") or ""), rate)] += int(line.get("taxable_paise") or 0)
        if inv.supply_type == SupplyType.INTER.value:
            tax[("IGST", rate)] += int(line.get("igst_paise") or 0)
        else:
            half = int(line.get("cgst_rate_bp") or rate // 2)
            tax[("CGST", half)] += int(line.get("cgst_paise") or 0)
            tax[("SGST", half)] += int(line.get("sgst_paise") or 0)
    for (hsn, rate), taxable in sorted(by_hsn.items()):
        entries.append(
            Entry(
                f"{acc.sales_ledger_prefix} @ {rate_text(rate)}%",
                credit,
                taxable,
                hsn=hsn or None,
                rate_bp=rate,
                taxable_paise=taxable,
            )
        )
    for (name, rate), amount in sorted(tax.items()):
        if amount:
            entries.append(
                Entry(f"{acc.output_tax_prefix} {name} @ {rate_text(rate)}%", credit, amount)
            )
    if inv.round_off_paise:
        # A positive round-off raised the total: it is income like the sale (credit side).
        positive = inv.round_off_paise > 0
        entries.append(
            Entry(
                acc.round_off_ledger, credit if positive else not credit, abs(inv.round_off_paise)
            )
        )
    return entries


def vouchers(data: AccountingDay, acc: AccountingSettings) -> list[Voucher]:
    out: list[Voucher] = []
    for inv in data.invoices:
        out.append(
            Voucher(
                kind="Sales",
                number=inv.invoice_no,
                when=inv.issued_at,
                reference=str(inv.order_id),
                party=inv.buyer_name,
                party_gstin=inv.buyer_gstin,
                place_of_supply=inv.place_of_supply,
                entries=tuple(_sale_entries(inv, acc, reverse=False)),
                narration=f"GST invoice {inv.invoice_no}",
            )
        )
    for inv in data.credit_notes:
        out.append(
            Voucher(
                kind="Credit Note",
                number=f"CN-{inv.invoice_no}",
                when=datetime.combine(data.day, datetime.min.time(), tzinfo=IST),
                reference=inv.invoice_no,
                party=inv.buyer_name,
                party_gstin=inv.buyer_gstin,
                place_of_supply=inv.place_of_supply,
                entries=tuple(_sale_entries(inv, acc, reverse=True)),
                narration=f"Order cancelled: reverses invoice {inv.invoice_no}",
            )
        )
    ledgers = {
        PaymentMode.CASH.value: acc.cash_ledger,
        PaymentMode.UPI_QR.value: acc.upi_ledger,
        PaymentMode.PAYMENT_LINK.value: acc.upi_ledger,
        PaymentMode.CARD_TERMINAL.value: acc.card_ledger,
    }
    for r in data.receipts:
        p = r.payment
        ref = p.provider_ref or p.reference_note or ""
        out.append(
            Voucher(
                kind="Receipt",
                number=f"RCPT-{str(p.id)[:8].upper()}",
                when=p.paid_at or p.created_at,
                reference=ref,
                party=r.party,
                party_gstin=None,
                place_of_supply=None,
                entries=(
                    Entry(ledgers.get(p.mode, acc.cash_ledger), True, p.amount_paise),
                    Entry(r.party, False, p.amount_paise),
                ),
                narration=f"{p.mode} receipt" + (f" for order {p.order_id}" if p.order_id else ""),
            )
        )
    return out


def tally_rows(data: AccountingDay, acc: AccountingSettings) -> list[list[Any]]:
    rows: list[list[Any]] = []
    for v in vouchers(data, acc):
        when = v.when.astimezone(IST).strftime("%d-%m-%Y")
        for e in v.entries:
            rows.append(
                [
                    when,
                    v.kind,
                    v.number,
                    v.reference,
                    v.party,
                    v.party_gstin or "",
                    v.place_of_supply or "",
                    e.ledger,
                    "Dr" if e.debit else "Cr",
                    rupees(e.amount_paise),
                    e.hsn or "",
                    rate_text(e.rate_bp) if e.rate_bp is not None else "",
                    rupees(e.taxable_paise) if e.taxable_paise is not None else "",
                    v.narration,
                ]
            )
    return rows


def zoho_rows(data: AccountingDay) -> list[list[Any]]:
    rows: list[list[Any]] = []
    for inv in data.invoices:
        intra = inv.supply_type == SupplyType.INTRA.value
        treatment = "business_gst" if inv.buyer_gstin else "consumer"
        for i, line in enumerate(inv.lines or []):
            rate = int(line.get("gst_rate_bp") or 0)
            tax = line.get("cgst_paise", 0) + line.get("sgst_paise", 0) + line.get("igst_paise", 0)
            rows.append(
                [
                    inv.issued_at.astimezone(IST).strftime("%Y-%m-%d"),
                    inv.invoice_no,
                    "Sent",
                    inv.buyer_name,
                    treatment,
                    inv.buyer_gstin or "",
                    inv.place_of_supply,
                    line.get("description") or "",
                    line.get("hsn") or "",
                    line.get("qty") or "",
                    line.get("unit") or "",
                    rupees(int(line.get("unit_price_paise") or 0)),
                    f"{'GST' if intra else 'IGST'}{rate_text(rate)}",
                    rate_text(rate),
                    "Tax Group" if intra else "Tax",
                    rupees(inv.round_off_paise) if i == 0 else "",
                    "Round off" if i == 0 and inv.round_off_paise else "",
                    "INR",
                    f"tax {rupees(int(tax))}",
                ]
            )
    return rows


def tally_xml(data: AccountingDay, acc: AccountingSettings, company: str) -> bytes:
    """Tally Prime / ERP 9 "Import Data -> Vouchers" envelope. In Tally XML a debit amount is
    negative with ``ISDEEMEDPOSITIVE=Yes`` and a credit positive with ``No``."""
    parts = [
        "<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY>"
        "<IMPORTDATA><REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME><STATICVARIABLES>"
        f"<SVCURRENTCOMPANY>{escape(company)}</SVCURRENTCOMPANY></STATICVARIABLES>"
        "</REQUESTDESC><REQUESTDATA>"
    ]
    for v in vouchers(data, acc):
        when = v.when.astimezone(IST).strftime("%Y%m%d")
        parts.append(
            f'<TALLYMESSAGE xmlns:UDF="TallyUDF"><VOUCHER VCHTYPE="{escape(v.kind)}" '
            f'ACTION="Create"><DATE>{when}</DATE>'
            f"<VOUCHERTYPENAME>{escape(v.kind)}</VOUCHERTYPENAME>"
            f"<VOUCHERNUMBER>{escape(v.number)}</VOUCHERNUMBER>"
            f"<REFERENCE>{escape(v.reference)}</REFERENCE>"
            f"<PARTYLEDGERNAME>{escape(v.party)}</PARTYLEDGERNAME>"
            f"<NARRATION>{escape(v.narration)}</NARRATION>"
        )
        if v.party_gstin:
            parts.append(f"<PARTYGSTIN>{escape(v.party_gstin)}</PARTYGSTIN>")
        if v.place_of_supply:
            parts.append(f"<PLACEOFSUPPLY>{escape(v.place_of_supply)}</PLACEOFSUPPLY>")
        for e in v.entries:
            amount = rupees(-e.amount_paise if e.debit else e.amount_paise)
            parts.append(
                "<ALLLEDGERENTRIES.LIST>"
                f"<LEDGERNAME>{escape(e.ledger)}</LEDGERNAME>"
                f"<ISDEEMEDPOSITIVE>{'Yes' if e.debit else 'No'}</ISDEEMEDPOSITIVE>"
                f"<AMOUNT>{amount}</AMOUNT>"
                "</ALLLEDGERENTRIES.LIST>"
            )
        parts.append("</VOUCHER></TALLYMESSAGE>")
    parts.append("</REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n' + "".join(parts)).encode("utf-8")


# --------------------------------------------------------------------------- resources
async def _load(session: AsyncSession, actor: User, filters: Any) -> AccountingDay:
    store = await visible_store(session, actor, filters.store_id)
    return await load_day(session, store, filters.day)


def _tally_source(
    session: AsyncSession, actor: User, filters: Any, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    async def rows() -> AsyncIterator[Sequence[Any]]:
        data = await _load(session, actor, filters)
        acc = (await get_tenant_settings(session, actor.tenant_id)).accounting
        for row in tally_rows(data, acc):
            yield row

    return rows()


def _zoho_source(
    session: AsyncSession, actor: User, filters: Any, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    async def rows() -> AsyncIterator[Sequence[Any]]:
        data = await _load(session, actor, filters)
        for row in zoho_rows(data):
            yield row

    return rows()


async def _tally_xml(
    session: AsyncSession, actor: User, filters: Any, now: datetime
) -> tuple[bytes, int]:
    data = await _load(session, actor, filters)
    settings = await get_tenant_settings(session, actor.tenant_id)
    company = settings.legal_name or data.store.name
    return tally_xml(data, settings.accounting, company), len(vouchers(data, settings.accounting))


def resources() -> list[Any]:
    from farmerapp.exports.resources import AccountingFilters, Resource

    return [
        Resource(
            "tally",
            ACCOUNTING_ROLES,
            AccountingFilters,
            TALLY_COLUMNS,
            _tally_source,
            description="ST-008 Tally CSV: sales, credit notes, receipts, GST breakup",
        ),
        Resource(
            "tally_xml",
            ACCOUNTING_ROLES,
            AccountingFilters,
            (),
            _tally_source,
            formats=frozenset({"xml"}),
            render={"xml": _tally_xml},
            description="ST-008 Tally voucher XML (Import Data -> Vouchers)",
        ),
        Resource(
            "zoho",
            ACCOUNTING_ROLES,
            AccountingFilters,
            ZOHO_COLUMNS,
            _zoho_source,
            description="ST-008 Zoho Books invoice import CSV",
        ),
    ]


__all__ = [
    "ACCOUNTING_ROLES",
    "TALLY_COLUMNS",
    "ZOHO_COLUMNS",
    "AccountingDay",
    "Voucher",
    "load_day",
    "resources",
    "rupees",
    "tally_rows",
    "tally_xml",
    "visible_store",
    "vouchers",
    "zoho_rows",
]
