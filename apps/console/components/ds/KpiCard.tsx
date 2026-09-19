"use client";

import * as React from "react";
import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";
import { Skeleton } from "./Skeleton";
import { trendColorClass, type Trend } from "./StatTile";

export interface KpiCardProps {
  title: string;
  /** Slot after the title (e.g. an InfoTip with the KPI definition). */
  titleAddon?: React.ReactNode;
  /** Formatted headline value (use lib/format). */
  value: string;
  /** Formatted target, e.g. "₹12 L". Shown with progress when `progress` is given. */
  target?: string;
  /** 0..1 progress toward target. */
  progress?: number;
  trend?: Trend;
  trendValue?: string;
  invertTrendColor?: boolean;
  /** Small chart or sparkline slot. */
  chart?: React.ReactNode;
  footer?: React.ReactNode;
  loading?: boolean;
  error?: string;
  onClick?: () => void;
  className?: string;
}

export function KpiCard({
  title,
  titleAddon,
  value,
  target,
  progress,
  trend,
  trendValue,
  invertTrendColor,
  chart,
  footer,
  loading,
  error,
  onClick,
  className,
}: KpiCardProps) {
  const t = useT();
  const Icon = trend === "up" ? ArrowUpRight : trend === "down" ? ArrowDownRight : Minus;
  const clamped = progress === undefined ? undefined : Math.max(0, Math.min(1, progress));
  const Wrapper: React.ElementType = onClick ? "button" : "div";
  return (
    <Wrapper
      type={onClick ? "button" : undefined}
      onClick={onClick}
      data-testid="kpi-card"
      aria-busy={loading || undefined}
      className={cn(
        "flex w-full flex-col gap-3 rounded-card border border-border bg-surface p-4 text-left",
        onClick &&
          "transition-colors hover:border-primary focus-visible:ring-2 focus-visible:ring-primary",
        error && "border-danger/50",
        className,
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <span className="inline-flex items-center gap-1 text-small font-semibold text-text-secondary">
          {title}
          {titleAddon}
        </span>
        {trend && !loading && !error ? (
          <span
            className={cn(
              "tnum inline-flex items-center gap-0.5 text-small font-semibold",
              trendColorClass(trend, invertTrendColor),
            )}
            data-trend={trend}
          >
            <Icon className="size-4" aria-hidden="true" />
            <span className="sr-only">
              {trend === "up"
                ? t("kpi.trendUp", { value: trendValue ?? "" })
                : trend === "down"
                  ? t("kpi.trendDown", { value: trendValue ?? "" })
                  : t("kpi.trendFlat")}
            </span>
            {trendValue ? <span aria-hidden="true">{trendValue}</span> : null}
          </span>
        ) : null}
      </div>
      {loading ? (
        <>
          <Skeleton className="h-9 w-32" />
          <Skeleton className="h-2 w-full" />
        </>
      ) : error ? (
        <p role="alert" className="text-small text-danger">
          {error}
        </p>
      ) : (
        <>
          <span className="tnum text-display font-semibold text-text" data-numeric>
            {value}
          </span>
          {target ? (
            <div className="flex flex-col gap-1">
              {clamped !== undefined ? (
                <div
                  className="h-1.5 w-full overflow-hidden rounded-pill bg-background"
                  role="progressbar"
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-valuenow={Math.round(clamped * 100)}
                  aria-label={t("kpi.target", { value: target })}
                >
                  <div
                    className={cn(
                      "h-full rounded-pill",
                      clamped >= 1 ? "bg-success" : "bg-primary",
                    )}
                    style={{ width: `${clamped * 100}%` }}
                  />
                </div>
              ) : null}
              <span className="tnum text-small text-text-muted">
                {t("kpi.target", { value: target })}
              </span>
            </div>
          ) : null}
          {chart ? <div className="h-12">{chart}</div> : null}
          {footer ? <div className="text-small text-text-secondary">{footer}</div> : null}
        </>
      )}
    </Wrapper>
  );
}
