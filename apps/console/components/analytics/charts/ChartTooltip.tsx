"use client";

import * as React from "react";

export interface TooltipRow {
  label: string;
  value: string;
  color: string;
  dashed?: boolean;
}

/** Tooltip body shared by the Recharts charts: token colours, values in text ink. */
export function ChartTooltipBox({ title, rows }: { title?: string; rows: TooltipRow[] }) {
  if (rows.length === 0) return null;
  return (
    <div className="rounded-input border border-border bg-surface px-3 py-2 text-small shadow-sheet">
      {title ? <p className="mb-1 font-semibold text-text">{title}</p> : null}
      <ul className="flex flex-col gap-0.5">
        {rows.map((r) => (
          <li key={r.label} className="flex items-center gap-2">
            <span
              aria-hidden="true"
              className="inline-block h-0.5 w-3"
              style={{
                background: r.dashed ? "transparent" : r.color,
                borderTop: r.dashed ? `2px dashed ${r.color}` : undefined,
              }}
            />
            <span className="text-text-secondary">{r.label}</span>
            <span className="tnum ml-auto pl-3 font-semibold text-text">{r.value}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Legend row (always shown for two or more series; identity is never colour alone). */
export function ChartLegend({
  items,
}: {
  items: Array<{ label: string; color: string; dashed?: boolean; shape?: "line" | "square" }>;
}) {
  return (
    <ul className="flex flex-wrap gap-x-4 gap-y-1 text-small text-text-secondary">
      {items.map((i) => (
        <li key={i.label} className="flex items-center gap-1.5">
          {i.shape === "square" ? (
            <span
              aria-hidden="true"
              className="inline-block size-2.5 rounded-[2px]"
              style={{ background: i.color }}
            />
          ) : (
            <span
              aria-hidden="true"
              className="inline-block w-4"
              style={{ borderTop: `2px ${i.dashed ? "dashed" : "solid"} ${i.color}` }}
            />
          )}
          {i.label}
        </li>
      ))}
    </ul>
  );
}
