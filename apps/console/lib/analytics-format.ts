/**
 * Formatting for the analytics screens on top of lib/format.ts: IST calendar days arrive as
 * `YYYY-MM-DD` strings (never shifted through a time zone), timestamps as UTC RFC 3339 and
 * are shown DD-MM-YYYY / HH:mm in IST, ratios may be null ("—").
 */
import {
  IST_TIME_ZONE,
  formatDuration,
  formatInr,
  formatInrCompact,
  formatNumber,
  formatPercent,
} from "./format";

import { CROP_STAGES, type CropStage } from "./analytics";
import type { TFunction } from "./i18n";

const DAY = /^(\d{4})-(\d{2})-(\d{2})$/;

/** `2026-08-01` -> `01-08-2026`. */
export function formatDay(day: string | null | undefined): string {
  const m = day ? DAY.exec(day) : null;
  return m ? `${m[3]}-${m[2]}-${m[1]}` : "—";
}

/** `2026-08-01` -> `01-08` (chart axes). */
export function formatDayShort(day: string): string {
  const m = DAY.exec(day);
  return m ? `${m[3]}-${m[2]}` : day;
}

/** `2026-08` -> `08-2026`. */
export function formatMonth(month: string): string {
  const m = /^(\d{4})-(\d{2})$/.exec(month);
  return m ? `${m[2]}-${m[1]}` : month;
}

export function formatRange(from: string, to: string): string {
  return from === to ? formatDay(from) : `${formatDay(from)} – ${formatDay(to)}`;
}

/** HH:mm in IST. */
export function formatTimeIst(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: IST_TIME_ZONE,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  })
    .format(d)
    .replace(/^24/, "00");
}

export function formatSeconds(s: number | null | undefined): string {
  return s === null || s === undefined ? "—" : formatDuration(s / 60);
}

export const formatRatio = (r: number | null | undefined, decimals = 1): string =>
  r === null || r === undefined ? "—" : formatPercent(r, decimals);

export const formatInrOrDash = (p: number | null | undefined): string =>
  p === null || p === undefined ? "—" : formatInr(p, { paise: "never" });

export const formatInrShort = (p: number | null | undefined): string =>
  p === null || p === undefined ? "—" : formatInrCompact(p);

export const formatDecimal = (n: number | null | undefined, decimals = 1): string =>
  n === null || n === undefined ? "—" : formatNumber(n, { decimals });

export const formatCount = (n: number | null | undefined): string =>
  n === null || n === undefined ? "—" : formatNumber(Math.round(n));

export const VISIT_PURPOSES = [
  "advisory",
  "follow_up",
  "collection",
  "demo",
  "registration",
  "delivery",
] as const;
export type VisitPurposeKey = (typeof VISIT_PURPOSES)[number] | "other";

/** Visit purpose -> copy key suffix (`purpose.*`); unknown values read "Other". */
export function purposeKey(p: string): VisitPurposeKey {
  return (VISIT_PURPOSES as readonly string[]).includes(p) ? (p as VisitPurposeKey) : "other";
}

export type VisitStatusKey = "verified" | "partial" | "unverified" | "open";

export function visitStatusKey(s: string): VisitStatusKey {
  return s === "verified" || s === "partial" || s === "unverified" ? s : "open";
}

/** Crop stage label (`stage.*`); unknown stages are shown as sent. */
export function stageLabel(s: string | null | undefined, t: TFunction): string {
  if (!s) return "—";
  return (CROP_STAGES as readonly string[]).includes(s) ? t(`stage.${s as CropStage}`) : s;
}
