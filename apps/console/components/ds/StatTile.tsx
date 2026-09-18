"use client";

import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";
import { Skeleton } from "./Skeleton";

export type Trend = "up" | "down" | "flat";

export interface StatTileProps {
  value: string | number;
  label: string;
  trend?: Trend;
  /** Formatted delta text, e.g. "+12%" (shown next to the arrow). */
  trendValue?: string;
  /** When true, an upward trend is bad (e.g. overdue credit). */
  invertTrendColor?: boolean;
  loading?: boolean;
  className?: string;
}

export function trendColorClass(trend: Trend, invert = false): string {
  if (trend === "flat") return "text-text-muted";
  const positive = trend === "up" ? !invert : invert;
  return positive ? "text-success" : "text-danger";
}

export function StatTile({
  value,
  label,
  trend,
  trendValue,
  invertTrendColor,
  loading,
  className,
}: StatTileProps) {
  const t = useT();
  const Icon = trend === "up" ? ArrowUpRight : trend === "down" ? ArrowDownRight : Minus;
  const trendLabel =
    trend === "up"
      ? t("kpi.trendUp", { value: trendValue ?? "" })
      : trend === "down"
        ? t("kpi.trendDown", { value: trendValue ?? "" })
        : t("kpi.trendFlat");
  return (
    <div
      data-testid="stat-tile"
      className={cn(
        "flex min-w-[140px] flex-col gap-1 rounded-card border border-border bg-surface p-4",
        className,
      )}
      aria-busy={loading || undefined}
    >
      {loading ? (
        <>
          <Skeleton className="h-7 w-24" />
          <Skeleton className="h-4 w-16" />
        </>
      ) : (
        <>
          <div className="flex items-baseline gap-2">
            <span className="tnum text-title font-semibold text-text" data-numeric>
              {value}
            </span>
            {trend ? (
              <span
                className={cn(
                  "tnum inline-flex items-center gap-0.5 text-small font-semibold",
                  trendColorClass(trend, invertTrendColor),
                )}
                data-trend={trend}
              >
                <Icon className="size-4" aria-hidden="true" />
                <span className="sr-only">{trendLabel}</span>
                {trendValue ? <span aria-hidden="true">{trendValue}</span> : null}
              </span>
            ) : null}
          </div>
          <span className="text-small text-text-secondary">{label}</span>
        </>
      )}
    </div>
  );
}
