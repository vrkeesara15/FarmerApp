"use client";

/** Line chart for trends (SPEC 13.4 "line for trends"). Loaded lazily (charts/index.tsx). */
import * as React from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { CHART } from "./palette";
import { ChartLegend, ChartTooltipBox } from "./ChartTooltip";

export interface LineSeries {
  key: string;
  label: string;
  color: string;
  dashed?: boolean;
}

export interface LineTrendProps {
  data: ReadonlyArray<Record<string, string | number | null>>;
  xKey: string;
  series: ReadonlyArray<LineSeries>;
  yFormat: (v: number) => string;
  xFormat?: (v: string) => string;
  /** Tooltip title per x value (defaults to xFormat). */
  titleFormat?: (v: string) => string;
  height?: number;
  label: string;
  yDomain?: [number | "auto", number | "auto"];
}

export default function LineTrend({
  data,
  xKey,
  series,
  yFormat,
  xFormat = (v) => v,
  titleFormat,
  height = 240,
  label,
  yDomain,
}: LineTrendProps) {
  return (
    <figure aria-label={label} className="flex flex-col gap-2" data-testid="line-chart">
      {series.length > 1 ? <ChartLegend items={[...series]} /> : null}
      <div style={{ height }}>
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={[...data]} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
            <CartesianGrid stroke={CHART.grid} strokeDasharray="0" vertical={false} />
            <XAxis
              dataKey={xKey}
              tickFormatter={(v: string) => xFormat(String(v))}
              stroke={CHART.axis}
              tick={{ fill: CHART.axis, fontSize: 12 }}
              tickLine={false}
              axisLine={{ stroke: CHART.grid }}
              minTickGap={24}
            />
            <YAxis
              tickFormatter={(v: number) => yFormat(v)}
              stroke={CHART.axis}
              tick={{ fill: CHART.axis, fontSize: 12 }}
              tickLine={false}
              axisLine={false}
              width={72}
              domain={yDomain}
            />
            <Tooltip
              cursor={{ stroke: CHART.axis, strokeWidth: 1 }}
              content={({ active, payload, label: x }) =>
                active && payload?.length ? (
                  <ChartTooltipBox
                    title={(titleFormat ?? xFormat)(String(x))}
                    rows={series
                      .map((s) => {
                        const p = payload.find((q) => q.dataKey === s.key);
                        const v = p?.value;
                        return typeof v === "number"
                          ? { label: s.label, value: yFormat(v), color: s.color, dashed: s.dashed }
                          : null;
                      })
                      .filter((r): r is NonNullable<typeof r> => r !== null)}
                  />
                ) : null
              }
            />
            {series.map((s) => (
              <Line
                key={s.key}
                type="monotone"
                dataKey={s.key}
                name={s.label}
                stroke={s.color}
                strokeWidth={2}
                strokeDasharray={s.dashed ? "5 4" : undefined}
                dot={false}
                activeDot={{ r: 4, stroke: CHART.surface, strokeWidth: 2 }}
                connectNulls={false}
                isAnimationActive={false}
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      </div>
    </figure>
  );
}
