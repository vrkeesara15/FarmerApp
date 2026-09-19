"use client";

/**
 * Lazy chart entry points: Recharts is split out of the page bundle and never rendered on the
 * server (`ssr: false`); a skeleton of the chart's height holds the space meanwhile.
 */
import dynamic from "next/dynamic";
import { Skeleton } from "@/components/ds/Skeleton";

function ChartSkeleton() {
  return <Skeleton className="h-60 w-full" data-testid="chart-skeleton" />;
}

export const LineTrend = dynamic(() => import("./LineTrend"), {
  ssr: false,
  loading: ChartSkeleton,
});
export const BarCompare = dynamic(() => import("./BarCompare"), {
  ssr: false,
  loading: ChartSkeleton,
});
export const ShareDonut = dynamic(() => import("./ShareDonut"), {
  ssr: false,
  loading: () => <Skeleton className="size-44 rounded-pill" />,
});
export type { LineSeries, LineTrendProps } from "./LineTrend";
export type { BarSeries, BarCompareProps } from "./BarCompare";
export { Sparkline } from "./Sparkline";
export { CHART, CHART_SERIES, BAND_COLOR, VISIT_COLOR } from "./palette";
