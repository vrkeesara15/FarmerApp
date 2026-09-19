import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { KpiTile } from "@/components/analytics/KpiTile";
import type { KpiOut } from "./analytics";
import { t } from "./i18n";
import { formatDelta, formatKpiValue, kpiView, trendDirection } from "./kpi";

const series = (...values: Array<number | null>) =>
  values.map((value, i) => ({ start: `2026-09-0${i + 1}`, end: `2026-09-0${i + 1}`, value }));

const revenue: KpiOut = {
  key: "revenue",
  unit: "paise",
  value: 1_25_00_000_00, // ₹1.25 Cr
  target: 1_00_00_000_00,
  last_year: 1_00_00_000_00,
  trend: series(10_00_000_00, 12_00_000_00, 15_00_000_00),
};

describe("KPI formatting (C10)", () => {
  it("formats paise with Indian units, ratios as %, counts with Indian grouping", () => {
    expect(formatKpiValue("paise", 12_500_000)).toBe("₹1.25 L");
    expect(formatKpiValue("paise", 1_25_00_000_00)).toBe("₹1.25 Cr");
    expect(formatKpiValue("ratio", 0.4567)).toBe("45.7%");
    expect(formatKpiValue("count", 1234567)).toBe("12,34,567");
    expect(formatKpiValue("count", null)).toBe("—");
  });

  it("deltas: relative % for amounts, percentage points for ratios, none from zero", () => {
    expect(formatDelta("paise", 125, 100, t)).toBe("+25%");
    expect(formatDelta("count", 90, 100, t)).toBe("-10%");
    expect(formatDelta("ratio", 0.45, 0.4, t)).toBe("+5.0 pts");
    expect(formatDelta("count", 5, 0, t)).toBeUndefined();
  });

  it("trend arrow from the period's own series; flat within 0.5 %", () => {
    expect(trendDirection(series(1, 2, 3), "count")).toBe("up");
    expect(trendDirection(series(3, null, 1), "count")).toBe("down");
    expect(trendDirection(series(1000, 1002), "count")).toBe("flat");
    expect(trendDirection(series(5), "count")).toBeUndefined();
    expect(trendDirection(series(0.4, 0.402), "ratio")).toBe("flat");
  });

  it("builds the card: value, target with progress, last-year comparison, trend", () => {
    const v = kpiView(revenue, t);
    expect(v).toMatchObject({
      title: "Revenue",
      value: "₹1.25 Cr",
      target: "₹1 Cr",
      progress: 1,
      trend: "up",
      trendValue: "+50%",
      invertTrendColor: false,
      lastYear: "Last year ₹1 Cr (+25%)",
    });
    expect(v.definition).toMatch(/Net sales/);
  });

  it("lower-is-better KPIs invert the arrow colour and show no progress bar", () => {
    const v = kpiView(
      {
        key: "credit_overdue",
        unit: "paise",
        value: 50_000_00,
        target: 40_000_00,
        last_year: null,
        trend: series(1, 2),
      },
      t,
    );
    expect(v.invertTrendColor).toBe(true);
    expect(v.progress).toBeUndefined();
    expect(v.target).toBe("₹40 K");
    expect(v.lastYear).toBeUndefined();
  });

  it("renders the tile with the SPEC 5.2 definition as a tooltip", () => {
    render(
      <KpiTile
        kpi={{
          ...revenue,
          key: "verified_visits",
          unit: "count",
          value: 1234,
          target: 2000,
          last_year: 1000,
          trend: series(10, 20),
        }}
      />,
    );
    const tile = screen.getByTestId("kpi-verified_visits");
    expect(within(tile).getByText("1,234")).toBeInTheDocument();
    expect(within(tile).getByText("Target 2,000")).toBeInTheDocument();
    expect(within(tile).getByText("Last year 1,000 (+23.4%)")).toBeInTheDocument();
    expect(within(tile).getByRole("progressbar")).toHaveAttribute("aria-valuenow", "62");
    expect(within(tile).getByRole("tooltip")).toHaveTextContent(
      "A visit with a score of 70 or more.",
    );
    expect(within(tile).getByTestId("sparkline")).toBeInTheDocument();
  });
});
