"use client";

/** One C10 KPI: value, target + progress, last-year comparison, trend arrow and sparkline. */
import * as React from "react";
import { KpiCard } from "@/components/ds/KpiCard";
import type { KpiOut } from "@/lib/analytics";
import { useT } from "@/lib/i18n-client";
import { kpiView } from "@/lib/kpi";
import { Sparkline } from "./charts/Sparkline";
import { CHART_SERIES } from "./charts/palette";
import { InfoTip } from "./InfoTip";

export function KpiTile({ kpi }: { kpi: KpiOut }) {
  const t = useT();
  const v = kpiView(kpi, t);
  return (
    <div data-testid={`kpi-${kpi.key}`}>
      <KpiCard
        title={v.title}
        titleAddon={v.definition ? <InfoTip name={v.title} text={v.definition} /> : null}
        value={v.value}
        target={v.target}
        progress={v.progress}
        trend={v.trend}
        trendValue={v.trendValue}
        invertTrendColor={v.invertTrendColor}
        chart={
          kpi.trend.length > 1 ? (
            <Sparkline
              values={kpi.trend.map((p) => p.value)}
              label={t("analytics.trendOf", { name: v.title })}
              width={200}
              height={40}
              color={CHART_SERIES[0]}
              className="w-full"
            />
          ) : undefined
        }
        footer={v.lastYear ?? t("kpi.noLastYear")}
      />
    </div>
  );
}
