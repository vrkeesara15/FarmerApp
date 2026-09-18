/**
 * Formatting helpers. Money is integer paise (CLAUDE.md). Indian digit grouping
 * (1,25,000) is implemented by hand so output does not depend on the ICU build.
 * Dates render DD-MM-YYYY in IST (Asia/Kolkata).
 */

export const IST_TIME_ZONE = "Asia/Kolkata";
const RUPEE = "\u20B9";

/** Group an unsigned integer string in Indian style: 1234567 -> "12,34,567". */
export function groupIndian(digits: string): string {
  const clean = digits.replace(/\D/g, "");
  if (clean.length <= 3) return clean;
  const last3 = clean.slice(-3);
  const rest = clean.slice(0, -3);
  const pairs = rest.replace(/\B(?=(\d{2})+(?!\d))/g, ",");
  return `${pairs},${last3}`;
}

export interface FormatNumberOptions {
  /** Fixed number of decimals; default keeps the number's own decimals (max 2). */
  decimals?: number;
}

/** Format a number with Indian grouping. */
export function formatNumber(value: number, options: FormatNumberOptions = {}): string {
  if (!Number.isFinite(value)) return "—";
  const negative = value < 0;
  const abs = Math.abs(value);
  const decimals = options.decimals ?? (Number.isInteger(abs) ? 0 : 2);
  const fixed = abs.toFixed(decimals);
  const [intPart = "0", fracPart] = fixed.split(".");
  const grouped = groupIndian(intPart);
  const out = fracPart !== undefined && decimals > 0 ? `${grouped}.${fracPart}` : grouped;
  return negative ? `-${out}` : out;
}

export type PaiseDisplay = "auto" | "always" | "never";

export interface FormatInrOptions {
  /** auto (default): show paise only when non-zero; always: 2 decimals; never: whole rupees (rounded). */
  paise?: PaiseDisplay;
  /** Include the ₹ symbol (default true). */
  symbol?: boolean;
}

/** Format integer paise as rupees with Indian grouping: 12500000 -> "₹1,25,000". */
export function formatInr(paise: number, options: FormatInrOptions = {}): string {
  if (!Number.isFinite(paise)) return "—";
  const { paise: mode = "auto", symbol = true } = options;
  const negative = paise < 0;
  let abs = Math.abs(Math.round(paise));
  if (mode === "never") abs = Math.round(abs / 100) * 100;
  const rupees = Math.floor(abs / 100);
  const remainder = abs % 100;
  const showPaise = mode === "always" || (mode === "auto" && remainder !== 0);
  const body = showPaise
    ? `${groupIndian(String(rupees))}.${String(remainder).padStart(2, "0")}`
    : groupIndian(String(rupees));
  return `${negative ? "-" : ""}${symbol ? RUPEE : ""}${body}`;
}

/** Compact rupees for KPI tiles: 12500000 paise -> "₹1.25 L"; 1e9 paise -> "₹1 Cr". */
export function formatInrCompact(paise: number): string {
  if (!Number.isFinite(paise)) return "—";
  const negative = paise < 0;
  const rupees = Math.abs(paise) / 100;
  const sign = negative ? "-" : "";
  const trim = (n: number) => n.toFixed(2).replace(/\.?0+$/, "");
  if (rupees >= 1_00_00_000) return `${sign}${RUPEE}${trim(rupees / 1_00_00_000)} Cr`;
  if (rupees >= 1_00_000) return `${sign}${RUPEE}${trim(rupees / 1_00_000)} L`;
  if (rupees >= 1_000) return `${sign}${RUPEE}${trim(rupees / 1_000)} K`;
  return `${sign}${RUPEE}${trim(rupees)}`;
}

/** Percentage with up to one decimal: 0.4567 -> "45.7%". */
export function formatPercent(ratio: number, decimals = 1): string {
  if (!Number.isFinite(ratio)) return "—";
  return `${formatNumber(ratio * 100, { decimals })}%`;
}

function partsInIst(date: Date): {
  day: string;
  month: string;
  year: string;
  hour: string;
  minute: string;
} {
  const fmt = new Intl.DateTimeFormat("en-GB", {
    timeZone: IST_TIME_ZONE,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const map: Record<string, string> = {};
  for (const p of fmt.formatToParts(date)) map[p.type] = p.value;
  return {
    day: map.day ?? "00",
    month: map.month ?? "00",
    year: map.year ?? "0000",
    hour: (map.hour ?? "00").replace("24", "00"),
    minute: map.minute ?? "00",
  };
}

function toDate(input: Date | string | number): Date | null {
  const d = input instanceof Date ? input : new Date(input);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** DD-MM-YYYY in IST. */
export function formatDateIst(input: Date | string | number): string {
  const d = toDate(input);
  if (!d) return "—";
  const { day, month, year } = partsInIst(d);
  return `${day}-${month}-${year}`;
}

/** DD-MM-YYYY HH:mm in IST (24h). */
export function formatDateTimeIst(input: Date | string | number): string {
  const d = toDate(input);
  if (!d) return "—";
  const { day, month, year, hour, minute } = partsInIst(d);
  return `${day}-${month}-${year} ${hour}:${minute}`;
}

/** Duration in whole minutes -> "1h 05m" / "45m". */
export function formatDuration(minutes: number): string {
  if (!Number.isFinite(minutes) || minutes < 0) return "—";
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  return h > 0 ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
}

/** Normalise an Indian mobile number to 10 digits, or null when invalid. */
export function normaliseIndianMobile(raw: string): string | null {
  const digits = raw.replace(/\D/g, "");
  const ten = digits.length === 12 && digits.startsWith("91") ? digits.slice(2) : digits;
  return /^[6-9]\d{9}$/.test(ten) ? ten : null;
}
