"use client";

/**
 * Own-brand share donut — the only pie-type chart allowed in the console (SPEC 13.4, C10).
 * Two slices, own brand (Turmeric) vs multi-brand (neutral), with the share as the hero
 * number in the middle and a labelled legend with values.
 */
import * as React from "react";
import { Cell, Pie, PieChart, ResponsiveContainer } from "recharts";
import { CHART } from "./palette";

export interface ShareDonutProps {
  /** 0..1 */
  share: number;
  ownLabel: string;
  otherLabel: string;
  ownValue: string;
  otherValue: string;
  centerLabel: string;
  centerValue: string;
  label: string;
  size?: number;
}

export default function ShareDonut({
  share,
  ownLabel,
  otherLabel,
  ownValue,
  otherValue,
  centerLabel,
  centerValue,
  label,
  size = 180,
}: ShareDonutProps) {
  const own = Math.max(0, Math.min(1, share));
  const data = [
    { name: ownLabel, value: own, color: CHART.ownBrand },
    { name: otherLabel, value: 1 - own, color: CHART.multiBrand },
  ];
  return (
    <figure
      aria-label={label}
      className="flex flex-wrap items-center gap-4"
      data-testid="share-donut"
    >
      <div className="relative" style={{ width: size, height: size }}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              dataKey="value"
              innerRadius="68%"
              outerRadius="100%"
              startAngle={90}
              endAngle={-270}
              stroke={CHART.surface}
              strokeWidth={2}
              isAnimationActive={false}
            >
              {data.map((d) => (
                <Cell key={d.name} fill={d.color} />
              ))}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="tnum text-title font-semibold text-text">{centerValue}</span>
          <span className="text-small text-text-muted">{centerLabel}</span>
        </div>
      </div>
      <ul className="flex flex-col gap-2 text-small">
        <li className="flex items-center gap-2">
          <span
            aria-hidden="true"
            className="size-2.5 rounded-[2px]"
            style={{ background: CHART.ownBrand }}
          />
          <span className="text-text-secondary">{ownLabel}</span>
          <span className="tnum ml-2 font-semibold text-text">{ownValue}</span>
        </li>
        <li className="flex items-center gap-2">
          <span
            aria-hidden="true"
            className="size-2.5 rounded-[2px]"
            style={{ background: CHART.multiBrand }}
          />
          <span className="text-text-secondary">{otherLabel}</span>
          <span className="tnum ml-2 font-semibold text-text">{otherValue}</span>
        </li>
      </ul>
    </figure>
  );
}
