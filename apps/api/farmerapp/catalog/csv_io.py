"""CSV import / export of the product master and label claims (WC-005; WC-013 builds on it).

Import is **dry-run by default** and all or nothing: every line is validated first (the same
rules as the REST writes) and the report lists row-level errors (``row`` = CSV line number,
the header being line 1, ``column``, ``code``, ``message``). Rows are written only when
``dry_run`` is false *and* no line has an error.

* ``products`` — one line per SKU. The product is matched by brand + name (case-insensitive)
  and created or updated; the SKU by barcode (when given) or by pack size, then created or
  updated. A barcode already used by another product's SKU is ``barcode_exists``.
* ``label_claims`` — one line per claim, the SKU by barcode, crop and problem by code. Import
  **never approves** (SPEC 14.6): a new triple becomes a draft; a triple with an open draft
  updates that draft; a triple with an approved claim and different values becomes a new draft
  version superseding it (identical values are skipped).

Export streams the same columns (plus ``id`` / ``status`` for claims), so an export can be
edited and re-imported.
"""

from __future__ import annotations

import csv
import functools
import io
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from typing import Any

from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError
from farmerapp.auth.models import User
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import ClaimStatus, LabelClaim, PestOrDisease, Product, Sku
from farmerapp.catalog.service import CLAIM_FIELDS, validate_claim_target
from farmerapp.catalog.write_schemas import (
    CatalogKind,
    ImportReport,
    ImportRowError,
    LabelClaimCreate,
    ProductCreate,
    SkuCreate,
)

PRODUCT_COLUMNS: tuple[str, ...] = (
    "brand",
    "product_name",
    "category",
    "own_brand",
    "hsn",
    "gst_rate_percent",
    "active_ingredient",
    "formulation",
    "pack_size_value",
    "pack_size_unit",
    "barcode",
    "mrp_paise",
    "active",
)
PRODUCT_REQUIRED: frozenset[str] = frozenset(
    {"brand", "product_name", "category", "gst_rate_percent", "pack_size_value"}
    | {"pack_size_unit", "mrp_paise"}
)
CLAIM_COLUMNS: tuple[str, ...] = (
    "id",
    "status",
    "sku_barcode",
    "crop_code",
    "pest_code",
    "dose_per_acre",
    "dose_value",
    "dose_unit",
    "dose_per_tank_15l",
    "phi_days",
    "ppe_text",
    "safety_text",
    "source_ref",
    "efficacy_tier",
)
CLAIM_REQUIRED: frozenset[str] = frozenset(
    {"sku_barcode", "crop_code", "pest_code", "dose_per_acre", "dose_value", "dose_unit"}
    | {"phi_days", "source_ref"}
)
MAX_ROWS = 5000

#: Schema field -> CSV column, for pydantic error locations.
_FIELD_TO_COLUMN: dict[str, str] = {
    "name": "product_name",
    "gst_rate_bp": "gst_rate_percent",
    "product_id": "product_name",
    "sku_id": "sku_barcode",
    "crop_id": "crop_code",
    "pest_or_disease_id": "pest_code",
}


class ImportAbort(Exception):  # noqa: N818
    """The file itself is unusable (bad header, too many rows)."""

    def __init__(self, error: ImportRowError) -> None:
        super().__init__(error.message)
        self.error = error


@dataclass
class _Report:
    kind: CatalogKind
    rows_total: int = 0
    created: int = 0
    updated: int = 0
    errors: list[ImportRowError] = field(default_factory=list)
    bad_rows: set[int] = field(default_factory=set)
    #: Applied first and flushed (products before the SKUs that reference them).
    first: list[Callable[[], Any]] = field(default_factory=list)
    actions: list[Callable[[], Any]] = field(default_factory=list)

    def error(self, row: int, column: str | None, code: str, message: str) -> None:
        self.errors.append(ImportRowError(row=row, column=column, code=code, message=message))
        self.bad_rows.add(row)


def _truthy(value: str | None, default: bool) -> bool:
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "y"}


def _blank(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    return value or None


def _read(text: str, columns: tuple[str, ...], required: frozenset[str]) -> list[dict[str, str]]:
    reader = csv.DictReader(io.StringIO(text.lstrip("\ufeff")))
    header = [h.strip() for h in (reader.fieldnames or [])]
    missing = sorted(required - set(header))
    if missing:
        raise ImportAbort(
            ImportRowError(
                row=1,
                column=None,
                code="missing_columns",
                message="Missing columns: " + ", ".join(missing),
            )
        )
    unknown = sorted(set(header) - set(columns))
    if unknown:
        raise ImportAbort(
            ImportRowError(
                row=1,
                column=None,
                code="unknown_columns",
                message="Unknown columns: " + ", ".join(unknown),
            )
        )
    rows = [{(k or "").strip(): (v or "") for k, v in r.items()} for r in reader]
    if len(rows) > MAX_ROWS:
        raise ImportAbort(
            ImportRowError(
                row=1,
                column=None,
                code="too_many_rows",
                message=f"At most {MAX_ROWS} rows per file.",
            )
        )
    return rows


def _validation_errors(report: _Report, line: int, exc: ValidationError) -> None:
    for err in exc.errors():
        loc = [str(p) for p in err.get("loc", ())]
        name = loc[0] if loc else None
        column = _FIELD_TO_COLUMN.get(name, name) if name else None
        report.error(line, column, "invalid_value", str(err.get("msg", "invalid")))


# --------------------------------------------------------------------------- products
async def _import_products(
    session: AsyncSession, actor: User, rows: list[dict[str, str]], report: _Report
) -> None:
    tid = actor.tenant_id
    products = {
        (p.brand.lower(), p.name.lower()): p
        for p in (
            await session.execute(
                select(Product).where(Product.tenant_id == tid, Product.deleted_at.is_(None))
            )
        ).scalars()
    }
    skus = list(
        (
            await session.execute(select(Sku).where(Sku.tenant_id == tid, Sku.deleted_at.is_(None)))
        ).scalars()
    )
    by_barcode = {s.barcode: s for s in skus if s.barcode}
    planned_products: dict[tuple[str, str], Product] = {}
    seen_barcodes: dict[str, int] = {}
    touched_products: set[tuple[str, str]] = set()

    for n, raw in enumerate(rows):
        line = n + 2
        gst_raw = _blank(raw.get("gst_rate_percent"))
        gst_bp: Any = gst_raw
        if gst_raw is not None:
            try:
                gst_bp = int(Decimal(gst_raw) * 100)
            except InvalidOperation:
                report.error(line, "gst_rate_percent", "invalid_value", "Not a number.")
                continue
        try:
            pbody = ProductCreate(
                name=raw.get("product_name", ""),
                brand=raw.get("brand", ""),
                own_brand=_truthy(raw.get("own_brand"), False),
                category=raw.get("category", "").strip().lower(),
                hsn=_blank(raw.get("hsn")),
                gst_rate_bp=gst_bp,
                active_ingredient=_blank(raw.get("active_ingredient")),
                formulation=_blank(raw.get("formulation")),
                active=_truthy(raw.get("active"), True),
            )
        except ValidationError as exc:
            _validation_errors(report, line, exc)
            continue
        key = (pbody.brand.lower(), pbody.name.lower())
        try:
            sbody = SkuCreate(
                product_id=uuid.uuid4(),  # placeholder; resolved below
                pack_size_value=raw.get("pack_size_value", "").strip(),
                pack_size_unit=raw.get("pack_size_unit", "").strip().lower(),
                barcode=_blank(raw.get("barcode")),
                mrp_paise=raw.get("mrp_paise", "").strip(),
                active=_truthy(raw.get("active"), True),
            )
        except ValidationError as exc:
            _validation_errors(report, line, exc)
            continue
        if sbody.barcode:
            if sbody.barcode in seen_barcodes:
                report.error(
                    line,
                    "barcode",
                    "barcode_duplicate",
                    f"Barcode also on line {seen_barcodes[sbody.barcode]}.",
                )
                continue
            seen_barcodes[sbody.barcode] = line

        product = products.get(key) or planned_products.get(key)
        existing_sku: Sku | None = None
        if sbody.barcode and sbody.barcode in by_barcode:
            existing_sku = by_barcode[sbody.barcode]
            if product is None or existing_sku.product_id != product.id:
                report.error(
                    line,
                    "barcode",
                    "barcode_exists",
                    f"Barcode {sbody.barcode} belongs to another product.",
                )
                continue
        elif product is not None and product.id is not None:
            existing_sku = next(
                (
                    s
                    for s in skus
                    if s.product_id == product.id
                    and s.pack_size_value == sbody.pack_size_value
                    and s.pack_size_unit == sbody.pack_size_unit.value
                    and s.barcode is None
                ),
                None,
            )

        # Plan the product.
        if key not in touched_products:
            touched_products.add(key)
            if product is None:
                product = Product(
                    id=uuid.uuid4(),
                    tenant_id=tid,
                    **{**pbody.model_dump(), "category": pbody.category.value},
                )
                planned_products[key] = product
                report.created += 1
                report.first.append(functools.partial(session.add, product))
            else:
                target = product
                values = {**pbody.model_dump(), "category": pbody.category.value}
                values.pop("names", None)
                values.pop("description", None)
                values.pop("image_uri", None)
                if any(getattr(target, k) != v for k, v in values.items()):
                    report.updated += 1

                    def _update(t: Product = target, v: dict[str, Any] = values) -> None:
                        for k, val in v.items():
                            setattr(t, k, val)

                    report.actions.append(_update)
        if product is None:  # unreachable: planned above
            continue
        # Plan the SKU.
        if existing_sku is None:
            new_sku = Sku(
                tenant_id=tid,
                product_id=product.id,
                pack_size_value=sbody.pack_size_value,
                pack_size_unit=sbody.pack_size_unit.value,
                barcode=sbody.barcode,
                mrp_paise=sbody.mrp_paise,
                active=sbody.active,
            )
            report.created += 1
            report.actions.append(functools.partial(session.add, new_sku))
        else:
            sku_values: dict[str, Any] = {
                "pack_size_value": sbody.pack_size_value,
                "pack_size_unit": sbody.pack_size_unit.value,
                "mrp_paise": sbody.mrp_paise,
                "active": sbody.active,
            }
            if any(getattr(existing_sku, k) != v for k, v in sku_values.items()):
                report.updated += 1

                def _update_sku(t: Sku = existing_sku, v: dict[str, Any] = sku_values) -> None:
                    for k, val in v.items():
                        setattr(t, k, val)

                report.actions.append(_update_sku)


# --------------------------------------------------------------------------- label claims
async def _import_claims(
    session: AsyncSession, actor: User, rows: list[dict[str, str]], report: _Report
) -> None:
    tid = actor.tenant_id
    skus = {
        s.barcode: s
        for s in (
            await session.execute(
                select(Sku).where(
                    Sku.tenant_id == tid, Sku.deleted_at.is_(None), Sku.barcode.is_not(None)
                )
            )
        ).scalars()
    }
    crops = {
        c.code: c
        for c in (
            await session.execute(
                select(Crop).where(Crop.tenant_id == tid, Crop.deleted_at.is_(None))
            )
        ).scalars()
    }
    pests = {
        p.code: p
        for p in (
            await session.execute(
                select(PestOrDisease).where(
                    PestOrDisease.tenant_id == tid, PestOrDisease.deleted_at.is_(None)
                )
            )
        ).scalars()
    }
    seen: dict[tuple[uuid.UUID, uuid.UUID, uuid.UUID], int] = {}
    for n, raw in enumerate(rows):
        line = n + 2
        sku = skus.get(raw.get("sku_barcode", "").strip())
        crop = crops.get(raw.get("crop_code", "").strip().lower())
        pest = pests.get(raw.get("pest_code", "").strip().lower())
        ok = True
        for value, column, what in (
            (sku, "sku_barcode", "SKU barcode"),
            (crop, "crop_code", "crop code"),
            (pest, "pest_code", "pest code"),
        ):
            if value is None:
                report.error(line, column, "not_found", f"Unknown {what}.")
                ok = False
        if not ok or sku is None or crop is None or pest is None:
            continue
        try:
            body = LabelClaimCreate(
                sku_id=sku.id,
                crop_id=crop.id,
                pest_or_disease_id=pest.id,
                dose_per_acre=raw.get("dose_per_acre", ""),
                dose_value=raw.get("dose_value", "").strip(),
                dose_unit=raw.get("dose_unit", "").strip().lower(),
                dose_per_tank_15l=_blank(raw.get("dose_per_tank_15l")),
                phi_days=raw.get("phi_days", "").strip(),
                ppe_text=_blank(raw.get("ppe_text")),
                safety_text=_blank(raw.get("safety_text")),
                source_ref=raw.get("source_ref", ""),
                efficacy_tier=_blank(raw.get("efficacy_tier")),
            )
        except ValidationError as exc:
            _validation_errors(report, line, exc)
            continue
        try:
            await validate_claim_target(
                session, tid, sku_id=sku.id, crop_id=crop.id, pest_or_disease_id=pest.id
            )
        except AppError as exc:
            report.error(line, "pest_code", exc.code, exc.detail or exc.code)
            continue
        triple = (sku.id, crop.id, pest.id)
        if triple in seen:
            report.error(line, None, "claim_duplicate", f"Same claim as line {seen[triple]}.")
            continue
        seen[triple] = line
        same = (
            (
                await session.execute(
                    select(LabelClaim).where(
                        LabelClaim.tenant_id == tid,
                        LabelClaim.sku_id == sku.id,
                        LabelClaim.crop_id == crop.id,
                        LabelClaim.pest_or_disease_id == pest.id,
                        LabelClaim.deleted_at.is_(None),
                        LabelClaim.status.in_(
                            [ClaimStatus.DRAFT.value, ClaimStatus.APPROVED.value]
                        ),
                    )
                )
            )
            .scalars()
            .all()
        )
        values = body.model_dump(include=set(CLAIM_FIELDS))
        values["dose_unit"] = body.dose_unit.value
        approved = next((c for c in same if c.status == ClaimStatus.APPROVED.value), None)
        drafts = [c for c in same if c.status == ClaimStatus.DRAFT.value]
        draft = next(
            (d for d in drafts if approved is not None and d.supersedes_id == approved.id),
            drafts[0] if drafts else None,
        )
        if draft is not None:
            if any(getattr(draft, k) != v for k, v in values.items()):
                report.updated += 1

                def _update(t: LabelClaim = draft, v: dict[str, Any] = values) -> None:
                    for k, val in v.items():
                        setattr(t, k, val)

                report.actions.append(_update)
            continue
        if approved is not None and all(getattr(approved, k) == v for k, v in values.items()):
            continue  # unchanged approved claim
        new = LabelClaim(
            tenant_id=tid,
            sku_id=sku.id,
            crop_id=crop.id,
            pest_or_disease_id=pest.id,
            status=ClaimStatus.DRAFT.value,
            supersedes_id=approved.id if approved is not None else None,
            **values,
        )
        report.created += 1
        report.actions.append(functools.partial(session.add, new))


async def import_catalog(
    session: AsyncSession, actor: User, *, kind: CatalogKind, text: str, dry_run: bool
) -> ImportReport:
    report = _Report(kind=kind)
    try:
        if kind is CatalogKind.PRODUCTS:
            rows = _read(text, PRODUCT_COLUMNS, PRODUCT_REQUIRED)
            report.rows_total = len(rows)
            await _import_products(session, actor, rows, report)
        else:
            rows = _read(text, CLAIM_COLUMNS, CLAIM_REQUIRED)
            report.rows_total = len(rows)
            await _import_claims(session, actor, rows, report)
    except ImportAbort as abort:
        report.errors.append(abort.error)
        report.bad_rows.add(1)
    applied = False
    if not dry_run and not report.errors:
        for action in report.first:
            action()
        await session.flush()
        for action in report.actions:
            action()
        await session.flush()
        applied = True
    return ImportReport(
        kind=kind,
        dry_run=dry_run,
        applied=applied,
        rows_total=report.rows_total,
        rows_ok=report.rows_total - len(report.bad_rows - {1}),
        created=report.created,
        updated=report.updated,
        errors=report.errors,
    )


# --------------------------------------------------------------------------- export
def _cell(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, Decimal):
        return f"{value.normalize():f}"
    return str(value)


def _csv_line(values: list[Any]) -> str:
    buf = io.StringIO()
    csv.writer(buf, lineterminator="\n").writerow([_cell(v) for v in values])
    return buf.getvalue()


async def export_rows(session: AsyncSession, tenant_id: uuid.UUID, kind: CatalogKind) -> list[str]:
    """CSV lines (header first); loaded up front so streaming needs no open session."""
    if kind is CatalogKind.PRODUCTS:
        product_rows = (
            await session.execute(
                select(Product, Sku)
                .join(Sku, Sku.product_id == Product.id)
                .where(
                    Product.tenant_id == tenant_id,
                    Product.deleted_at.is_(None),
                    Sku.deleted_at.is_(None),
                )
                .order_by(func.lower(Product.brand), func.lower(Product.name), Sku.pack_size_value)
            )
        ).tuples()
        lines = [_csv_line(list(PRODUCT_COLUMNS))]
        for p, s in product_rows:
            lines.append(
                _csv_line(
                    [
                        p.brand,
                        p.name,
                        p.category,
                        p.own_brand,
                        p.hsn,
                        Decimal(p.gst_rate_bp) / 100,
                        p.active_ingredient,
                        p.formulation,
                        s.pack_size_value,
                        s.pack_size_unit,
                        s.barcode,
                        s.mrp_paise,
                        p.active and s.active,
                    ]
                )
            )
        return lines
    claim_rows = (
        await session.execute(
            select(LabelClaim, Sku.barcode, Crop.code, PestOrDisease.code)
            .join(Sku, Sku.id == LabelClaim.sku_id)
            .join(Crop, Crop.id == LabelClaim.crop_id)
            .join(PestOrDisease, PestOrDisease.id == LabelClaim.pest_or_disease_id)
            .where(LabelClaim.tenant_id == tenant_id, LabelClaim.deleted_at.is_(None))
            .order_by(Crop.code, PestOrDisease.code, Sku.barcode, LabelClaim.created_at)
        )
    ).tuples()
    lines = [_csv_line(list(CLAIM_COLUMNS))]
    for c, barcode, crop_code, pest_code in claim_rows:
        lines.append(
            _csv_line(
                [
                    c.id,
                    c.status,
                    barcode,
                    crop_code,
                    pest_code,
                    c.dose_per_acre,
                    c.dose_value,
                    c.dose_unit,
                    c.dose_per_tank_15l,
                    c.phi_days,
                    c.ppe_text,
                    c.safety_text,
                    c.source_ref,
                    c.efficacy_tier,
                ]
            )
        )
    return lines


def iter_lines(lines: list[str]) -> Iterator[bytes]:
    for line in lines:
        yield line.encode("utf-8")


__all__ = [
    "CLAIM_COLUMNS",
    "PRODUCT_COLUMNS",
    "export_rows",
    "import_catalog",
    "iter_lines",
]
