/**
 * Client-side CSV export of a table view (WC-013 adds scheduled exports later). RFC 4180
 * quoting, CRLF rows, a UTF-8 BOM so spreadsheet apps read Telugu / Kannada / Devanagari
 * names, and formula neutralisation (a text cell starting with = + - @ tab or CR gets a
 * leading apostrophe, same rule as the API's CSV exports).
 */
import { downloadText } from "./catalog";

export interface CsvColumn<Row> {
  header: string;
  value: (row: Row) => string | number | boolean | null | undefined;
}

const FORMULA_START = /^[=+\-@\t\r]/;

export function csvCell(value: string | number | boolean | null | undefined): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "number") return Number.isFinite(value) ? String(value) : "";
  let s = String(value);
  if (typeof value === "string" && FORMULA_START.test(s)) s = `'${s}`;
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function toCsv<Row>(
  columns: ReadonlyArray<CsvColumn<Row>>,
  rows: ReadonlyArray<Row>,
): string {
  const lines = [columns.map((c) => csvCell(c.header)).join(",")];
  for (const row of rows) lines.push(columns.map((c) => csvCell(c.value(row))).join(","));
  return `${lines.join("\r\n")}\r\n`;
}

export const CSV_BOM = "﻿";

/** `farmers_2026-08-01_2026-08-30.csv` */
export function csvFilename(base: string, from?: string, to?: string): string {
  return [base, from, to].filter(Boolean).join("_") + ".csv";
}

/** Rupees with two decimals for spreadsheets (money is integer paise everywhere else). */
export function paiseToRupees(paise: number | null | undefined): number | null {
  return paise === null || paise === undefined ? null : Math.round(paise) / 100;
}

export function downloadCsv<Row>(
  filename: string,
  columns: ReadonlyArray<CsvColumn<Row>>,
  rows: ReadonlyArray<Row>,
): void {
  downloadText(filename, CSV_BOM + toCsv(columns, rows), "text/csv;charset=utf-8");
}
