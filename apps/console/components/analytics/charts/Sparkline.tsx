"use client";

/**
 * Word-sized trend line for tables and KPI cards (C20 weekly sparklines). Plain SVG, no chart
 * library, so a 50-row scorecard stays cheap. The last point gets a dot; `label` describes
 * the values for screen readers.
 */
import * as React from "react";
import { cn } from "@/lib/utils";
import { CHART_SERIES } from "./palette";

export interface SparklineProps {
  values: ReadonlyArray<number | null>;
  label: string;
  width?: number;
  height?: number;
  color?: string;
  className?: string;
}

export function sparklinePath(
  values: ReadonlyArray<number | null>,
  width: number,
  height: number,
  pad = 2,
): { d: string; last: { x: number; y: number } | null } {
  const nums = values.filter((v): v is number => v !== null && Number.isFinite(v));
  if (nums.length === 0) return { d: "", last: null };
  const min = Math.min(...nums);
  const max = Math.max(...nums);
  const span = max - min || 1;
  const n = values.length;
  const x = (i: number) => (n === 1 ? width / 2 : pad + (i * (width - 2 * pad)) / (n - 1));
  const y = (v: number) =>
    max === min ? height / 2 : height - pad - ((v - min) * (height - 2 * pad)) / span;
  let d = "";
  let pen = false;
  let last: { x: number; y: number } | null = null;
  values.forEach((v, i) => {
    if (v === null || !Number.isFinite(v)) {
      pen = false;
      return;
    }
    const px = Math.round(x(i) * 10) / 10;
    const py = Math.round(y(v) * 10) / 10;
    d += `${pen ? "L" : "M"}${px} ${py} `;
    pen = true;
    last = { x: px, y: py };
  });
  return { d: d.trim(), last };
}

export function Sparkline({
  values,
  label,
  width = 96,
  height = 28,
  color = CHART_SERIES[0],
  className,
}: SparklineProps) {
  const { d, last } = sparklinePath(values, width, height);
  return (
    <svg
      role="img"
      aria-label={label}
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className={cn("overflow-visible", className)}
      data-testid="sparkline"
    >
      {d ? (
        <path d={d} fill="none" stroke={color} strokeWidth={1.5} strokeLinejoin="round" />
      ) : null}
      {last ? <circle cx={last.x} cy={last.y} r={2.5} fill={color} /> : null}
    </svg>
  );
}
