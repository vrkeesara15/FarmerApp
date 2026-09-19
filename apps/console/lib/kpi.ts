/**
 * KPI presentation (C10 KPI row, SPEC 5.1 AN-001 / 5.2). Pure formatting over the
 * `/v1/analytics/owner-home` `kpis[]` items: headline value, target with progress, last-year
 * comparison and a trend arrow from the period's own trend series.
 */
import type { KpiOut, KpiUnit, SeriesPoint } from "./analytics";
import { formatInrCompact, formatNumber, formatPercent } from "./format";
import type { MessageKey, TFunction } from "./i18n";
import type { Trend } from "@/components/ds/StatTile";

/** KPIs where a rise is bad (the arrow turns red when going up). */
export const LOWER_IS_BETTER = new Set(["credit_overdue", "open_flags"]);

/** Title and SPEC 5.2 definition (tooltip) per KPI key. */
export const KPI_COPY: Record<string, { title: MessageKey; definition: MessageKey }> = {
  revenue: { title: "kpis.revenue", definition: "kpiDefinitions.revenue" },
  own_brand_share: { title: "kpis.ownBrandShare", definition: "kpiDefinitions.ownBrandShare" },
  credit_outstanding: {
    title: "kpis.creditOutstanding",
    definition: "kpiDefinitions.creditOutstanding",
  },
  credit_overdue: { title: "kpis.creditOverdue", definition: "kpiDefinitions.creditOverdue" },
  verified_visits: { title: "kpis.verifiedVisits", definition: "kpiDefinitions.verifiedVisit" },
  active_farmers: { title: "kpis.activeFarmers", definition: "kpiDefinitions.activeFarmer" },
  open_flags: { title: "kpis.openFlags", definition: "kpiDefinitions.openFlags" },
};

export function formatKpiValue(unit: KpiUnit, value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  if (unit === "paise") return formatInrCompact(value);
  if (unit === "ratio") return formatPercent(value);
  return formatNumber(Math.round(value));
}

/** Signed change: relative % for amounts and counts, percentage points for ratios. */
export function formatDelta(
  unit: KpiUnit,
  current: number,
  base: number,
  t: TFunction,
): string | undefined {
  if (unit === "ratio") {
    const pts = (current - base) * 100;
    const sign = pts > 0 ? "+" : pts < 0 ? "-" : "";
    return t("kpi.points", { value: `${sign}${formatNumber(Math.abs(pts), { decimals: 1 })}` });
  }
  if (base === 0) return undefined;
  const pct = (current - base) / Math.abs(base);
  const sign = pct > 0 ? "+" : pct < 0 ? "-" : "";
  return `${sign}${formatPercent(Math.abs(pct)).replace(/\.0%$/, "%")}`;
}

function firstLast(series: SeriesPoint[]): [number, number] | null {
  const values = series.map((p) => p.value).filter((v): v is number => v !== null);
  if (values.length < 2) return null;
  return [values[0]!, values[values.length - 1]!];
}

/** Direction of the period's trend series (first vs last bucket); flat within 0.5 %. */
export function trendDirection(series: SeriesPoint[], unit: KpiUnit): Trend | undefined {
  const fl = firstLast(series);
  if (!fl) return undefined;
  const [a, b] = fl;
  const threshold = unit === "ratio" ? 0.005 : Math.max(Math.abs(a) * 0.005, 1e-9);
  if (Math.abs(b - a) <= threshold) return "flat";
  return b > a ? "up" : "down";
}

export interface KpiView {
  key: string;
  title: string;
  definition: string;
  value: string;
  target?: string;
  /** 0..1 progress to target (only where a higher value is better). */
  progress?: number;
  trend?: Trend;
  trendValue?: string;
  invertTrendColor: boolean;
  /** "Last year ₹1.2 L (+12%)" or undefined when there is no last-year figure. */
  lastYear?: string;
}

export function kpiView(kpi: KpiOut, t: TFunction): KpiView {
  const copy = KPI_COPY[kpi.key];
  const lowerIsBetter = LOWER_IS_BETTER.has(kpi.key);
  const view: KpiView = {
    key: kpi.key,
    title: copy ? t(copy.title) : kpi.key,
    definition: copy ? t(copy.definition) : "",
    value: formatKpiValue(kpi.unit, kpi.value),
    invertTrendColor: lowerIsBetter,
  };
  if (kpi.target !== null && kpi.target !== undefined) {
    view.target = formatKpiValue(kpi.unit, kpi.target);
    if (!lowerIsBetter && kpi.value !== null && kpi.target > 0)
      view.progress = Math.max(0, Math.min(1, kpi.value / kpi.target));
  }
  view.trend = trendDirection(kpi.trend, kpi.unit);
  const fl = firstLast(kpi.trend);
  if (fl && view.trend !== "flat") view.trendValue = formatDelta(kpi.unit, fl[1], fl[0], t);
  if (kpi.last_year !== null && kpi.last_year !== undefined && kpi.value !== null) {
    const delta = formatDelta(kpi.unit, kpi.value, kpi.last_year, t);
    const ly = formatKpiValue(kpi.unit, kpi.last_year);
    view.lastYear = delta
      ? t("kpi.lastYearDelta", { value: ly, delta })
      : t("kpi.lastYear", { value: ly });
  }
  return view;
}
