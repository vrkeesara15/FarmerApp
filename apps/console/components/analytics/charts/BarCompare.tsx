"use client";

/** Bar chart for comparisons (SPEC 13.4 "bars for comparisons"). Loaded lazily. */
import * as React from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { CHART } from "./palette";
import { ChartLegend, ChartTooltipBox } from "./ChartTooltip";

export interface BarSeries {
  key: string;
  label: string;
  color: string;
}

export interface BarCompareProps {
  data: ReadonlyArray<Record<string, string | number | null>>;
  categoryKey: string;
  series: ReadonlyArray<BarSeries>;
  valueFormat: (v: number) => string;
  categoryFormat?: (v: string) => string;
  /** Per-bar colour for single-series status bars (e.g. variance over the threshold). */
  colorFor?: (row: Record<string, string | number | null>) => string;
  /** "horizontal" = category on the y axis (long labels, rankings). */
  layout?: "vertical" | "horizontal";
  height?: number;
  label: string;
}

export default function BarCompare({
  data,
  categoryKey,
  series,
  valueFormat,
  categoryFormat = (v) => v,
  colorFor,
  layout = "vertical",
  height = 240,
  label,
}: BarCompareProps) {
  const horizontal = layout === "horizontal";
  const rows = [...data];
  const categoryAxis = {
    dataKey: categoryKey,
    tickFormatter: (v: string) => categoryFormat(String(v)),
    tick: { fill: CHART.axis, fontSize: 12 },
    tickLine: false,
    axisLine: { stroke: CHART.grid },
  };
  const valueAxis = {
    tickFormatter: (v: number) => valueFormat(v),
    tick: { fill: CHART.axis, fontSize: 12 },
    tickLine: false,
    axisLine: false,
  };
  return (
    <figure aria-label={label} className="flex flex-col gap-2" data-testid="bar-chart">
      {series.length > 1 ? (
        <ChartLegend items={series.map((s) => ({ ...s, shape: "square" as const }))} />
      ) : null}
      <div style={{ height }}>
        <ResponsiveContainer width="100%" height="100%">
          <BarChart
            data={rows}
            layout={horizontal ? "vertical" : "horizontal"}
            margin={{ top: 8, right: 12, bottom: 0, left: 0 }}
            barGap={2}
          >
            <CartesianGrid stroke={CHART.grid} horizontal={!horizontal} vertical={horizontal} />
            {horizontal ? (
              <>
                <XAxis type="number" {...valueAxis} />
                <YAxis type="category" width={120} {...categoryAxis} />
              </>
            ) : (
              <>
                <XAxis type="category" interval={0} minTickGap={4} {...categoryAxis} />
                <YAxis type="number" width={72} {...valueAxis} />
              </>
            )}
            <Tooltip
              cursor={{ fill: CHART.grid, opacity: 0.4 }}
              content={({ active, payload, label: c }) =>
                active && payload?.length ? (
                  <ChartTooltipBox
                    title={categoryFormat(String(c))}
                    rows={series
                      .map((s) => {
                        const p = payload.find((q) => q.dataKey === s.key);
                        const v = p?.value;
                        const color =
                          colorFor && p?.payload
                            ? colorFor(p.payload as Record<string, string | number | null>)
                            : s.color;
                        return typeof v === "number"
                          ? { label: s.label, value: valueFormat(v), color }
                          : null;
                      })
                      .filter((r): r is NonNullable<typeof r> => r !== null)}
                  />
                ) : null
              }
            />
            {series.map((s) => (
              <Bar
                key={s.key}
                dataKey={s.key}
                name={s.label}
                fill={s.color}
                radius={horizontal ? [0, 4, 4, 0] : [4, 4, 0, 0]}
                maxBarSize={28}
                isAnimationActive={false}
              >
                {colorFor ? rows.map((row, i) => <Cell key={i} fill={colorFor(row)} />) : null}
              </Bar>
            ))}
          </BarChart>
        </ResponsiveContainer>
      </div>
    </figure>
  );
}
