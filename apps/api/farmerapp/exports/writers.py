"""CSV and XLSX writers for exports (WC-013).

Rows arrive as an iterator (the database cursor is streamed in chunks) and are written
incrementally into a spooled temporary file, so a large export never holds every row as
Python objects; the finished file is handed to the ``BlobStore``.

* CSV: UTF-8 with a BOM (Excel opens Telugu / Kannada names correctly), ``\\r\\n`` line
  ends; a cell a spreadsheet would read as a formula is prefixed with ``'`` (CSV injection).
* XLSX: a minimal Office Open XML workbook (one sheet, inline strings — never evaluated as
  formulas — numbers as numbers)
  written with ``zipfile`` — no third-party dependency. Opened by Excel, LibreOffice and
  Google Sheets.
"""

from __future__ import annotations

import csv
import io
import json
import tempfile
import zipfile
from collections.abc import Iterable, Sequence
from datetime import date, datetime
from decimal import Decimal
from typing import IO, Any
from xml.sax.saxutils import escape  # nosec B406 - escaping only, no XML parsing

SPOOL_MAX_BYTES = 8 * 1024 * 1024
FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")
CSV_MEDIA_TYPE = "text/csv; charset=utf-8"
XLSX_MEDIA_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def cell_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, dict | list):
        return json.dumps(value, sort_keys=True, ensure_ascii=False, default=str)
    if isinstance(value, datetime | date):
        return value.isoformat()
    return str(value)


def safe_text(value: Any) -> str:
    text = cell_text(value)
    if isinstance(value, int | float | Decimal) and not isinstance(value, bool):
        return text  # a negative number is not a formula
    return "'" + text if text.startswith(FORMULA_PREFIXES) else text


class CsvWriter:
    """Incremental CSV into a spooled file: ``add(row)`` per row, then ``finish()``."""

    def __init__(self, columns: Sequence[str], *, bom: bool = True) -> None:
        self._out: IO[bytes] = tempfile.SpooledTemporaryFile(max_size=SPOOL_MAX_BYTES)  # noqa: SIM115
        self._text = io.TextIOWrapper(
            self._out, encoding="utf-8-sig" if bom else "utf-8", newline=""
        )
        self._writer = csv.writer(self._text, lineterminator="\r\n")
        self._writer.writerow(columns)
        self.count = 0

    def add(self, row: Sequence[Any]) -> None:
        self._writer.writerow([safe_text(v) for v in row])
        self.count += 1

    def finish(self) -> tuple[IO[bytes], int]:
        self._text.flush()
        self._text.detach()
        self._out.seek(0)
        return self._out, self.count


def write_csv(
    columns: Sequence[str], rows: Iterable[Sequence[Any]], *, bom: bool = True
) -> tuple[IO[bytes], int]:
    """Write to a spooled file; returns ``(file positioned at 0, data rows)``."""
    writer = CsvWriter(columns, bom=bom)
    for row in rows:
        writer.add(row)
    return writer.finish()


def _col(index: int) -> str:
    name = ""
    index += 1
    while index:
        index, rem = divmod(index - 1, 26)
        name = chr(65 + rem) + name
    return name


def _xml_cell(ref: str, value: Any) -> str:
    if isinstance(value, int | float | Decimal) and not isinstance(value, bool):
        return f'<c r="{ref}"><v>{value}</v></c>'
    # An inline string is never evaluated as a formula: no CSV-injection prefix needed.
    text = escape(cell_text(value))
    # XML 1.0 forbids most control characters: drop them.
    text = "".join(ch for ch in text if ch in "\t\n\r" or ord(ch) >= 32)
    return f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">{text}</t></is></c>'


_CONTENT_TYPES = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" '
    'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    "</Types>"
)
_ROOT_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/></Relationships>'
)
_WORKBOOK_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
    'Target="worksheets/sheet1.xml"/></Relationships>'
)


def _workbook(sheet: str) -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        f'<sheets><sheet name="{escape(sheet[:31])}" sheetId="1" r:id="rId1"/></sheets>'
        "</workbook>"
    )


class XlsxWriter:
    """Incremental single-sheet XLSX: the sheet XML is streamed into the zip entry."""

    def __init__(self, columns: Sequence[str], *, sheet: str = "Export") -> None:
        self._out: IO[bytes] = tempfile.SpooledTemporaryFile(max_size=SPOOL_MAX_BYTES)  # noqa: SIM115
        self._zip = zipfile.ZipFile(self._out, "w", compression=zipfile.ZIP_DEFLATED)
        self._zip.writestr("[Content_Types].xml", _CONTENT_TYPES)
        self._zip.writestr("_rels/.rels", _ROOT_RELS)
        self._zip.writestr("xl/workbook.xml", _workbook(sheet))
        self._zip.writestr("xl/_rels/workbook.xml.rels", _WORKBOOK_RELS)
        self._sheet = self._zip.open("xl/worksheets/sheet1.xml", "w")
        self._sheet.write(
            b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            b'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            b"<sheetData>"
        )
        header = "".join(_xml_cell(f"{_col(i)}1", str(c)) for i, c in enumerate(columns))
        self._sheet.write(f'<row r="1">{header}</row>'.encode())
        self.count = 0

    def add(self, row: Sequence[Any]) -> None:
        r = self.count + 2
        cells = "".join(_xml_cell(f"{_col(i)}{r}", v) for i, v in enumerate(row))
        self._sheet.write(f'<row r="{r}">{cells}</row>'.encode())
        self.count += 1

    def finish(self) -> tuple[IO[bytes], int]:
        self._sheet.write(b"</sheetData></worksheet>")
        self._sheet.close()
        self._zip.close()
        self._out.seek(0)
        return self._out, self.count


def write_xlsx(
    columns: Sequence[str], rows: Iterable[Sequence[Any]], *, sheet: str = "Export"
) -> tuple[IO[bytes], int]:
    writer = XlsxWriter(columns, sheet=sheet)
    for row in rows:
        writer.add(row)
    return writer.finish()


def read_xlsx_rows(data: bytes) -> list[list[str]]:
    """Test helper: the cell texts of the first sheet, row by row."""
    import re

    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        xml = zf.read("xl/worksheets/sheet1.xml").decode()
    rows: list[list[str]] = []
    for row in re.findall(r"<row [^>]*>(.*?)</row>", xml):
        cells = re.findall(r"<c [^>]*>(?:<v>(.*?)</v>|<is><t[^>]*>(.*?)</t></is>)</c>", row)
        rows.append([v or t for v, t in cells])
    return rows


__all__ = [
    "CSV_MEDIA_TYPE",
    "XLSX_MEDIA_TYPE",
    "CsvWriter",
    "XlsxWriter",
    "cell_text",
    "read_xlsx_rows",
    "safe_text",
    "write_csv",
    "write_xlsx",
]
