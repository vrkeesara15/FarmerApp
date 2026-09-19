"use client";

/**
 * C10 Owner home (WC-001 / AN-001). One `/v1/analytics/owner-home` call (the API answers in
 * ~1.2 s for 50 stores) fetched in parallel with the filter option lists; the KPI row renders
 * as soon as the payload arrives while the chart and map chunks stream in lazily behind
 * skeletons, so the first meaningful content does not wait for Recharts or Leaflet.
 */
import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { AlertTriangle, Sprout } from "lucide-react";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { EmptyState } from "@/components/ds/EmptyState";
import { KpiCard } from "@/components/ds/KpiCard";
import { SeverityBadge, type Severity } from "@/components/ds/SeverityBadge";
import { AnalyticsFilterBar } from "@/components/analytics/AnalyticsFilterBar";
import {
  BarCompare,
  CHART,
  CHART_SERIES,
  LineTrend,
  ShareDonut,
} from "@/components/analytics/charts";
import { KpiTile } from "@/components/analytics/KpiTile";
import { StoreMap } from "@/components/analytics/maps";
import {
  AnalyticsGate,
  PageHeader,
  ScopeNote,
  Section,
  SectionSkeleton,
} from "@/components/analytics/Page";
import { isBlockingProblem, ProblemState } from "@/components/analytics/ProblemState";
import { Badge } from "@/components/ui/badge";
import {
  OVERDUE_BUCKETS,
  type OfficerRankOut,
  type OwnerHomeOut,
  type StoreMapItem,
} from "@/lib/analytics";
import {
  formatDay,
  formatDayShort,
  formatDecimal,
  formatInrShort,
  formatRange,
  formatRatio,
} from "@/lib/analytics-format";
import { csvFilename, downloadCsv, paiseToRupees } from "@/lib/csv";
import { formatDateTimeIst } from "@/lib/format";
import { useFilterOptions, useOwnerHome } from "@/lib/hooks/analytics";
import { useAnalyticsFilters } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";

export function OwnerHomeView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C10">
      <AnalyticsGate path="/home" title={t("home.title")}>
        <OwnerHome />
      </AnalyticsGate>
    </div>
  );
}

const SEVERITIES: Severity[] = ["critical", "high", "medium", "low"];
const asSeverity = (s: string): Severity =>
  (SEVERITIES as string[]).includes(s) ? (s as Severity) : "high";

function OwnerHome() {
  const t = useT();
  const router = useRouter();
  const filters = useAnalyticsFilters();
  const q = useOwnerHome(filters.apiFilters);
  const opts = useFilterOptions();
  const data = q.data;

  const storeColumns = React.useMemo(
    () => [
      { header: t("stores.columns.store"), value: (s: StoreMapItem) => s.name },
      { header: t("stores.columns.district"), value: (s: StoreMapItem) => s.district },
      {
        header: t("home.storeTable.revenue"),
        value: (s: StoreMapItem) => paiseToRupees(s.revenue_paise),
      },
      { header: t("home.storeTable.ownBrandShare"), value: (s: StoreMapItem) => s.own_brand_share },
      {
        header: t("home.storeTable.overdue"),
        value: (s: StoreMapItem) => paiseToRupees(s.overdue_paise),
      },
      { header: t("home.storeTable.score"), value: (s: StoreMapItem) => s.score },
      { header: t("home.storeTable.band"), value: (s: StoreMapItem) => t(`home.band.${s.band}`) },
    ],
    [t],
  );

  const onExport = data
    ? () =>
        downloadCsv(
          csvFilename("owner-home-stores", filters.filters.from, filters.filters.to),
          storeColumns,
          data.stores,
        )
    : undefined;

  const header = (
    <PageHeader
      title={t("home.title")}
      subtitle={
        <span className="flex flex-wrap items-center gap-3">
          <span className="tnum">{formatRange(filters.filters.from, filters.filters.to)}</span>
          <ScopeNote scope={data?.filters.scope} />
          {q.isFetching && data ? (
            <span className="text-small text-text-muted">{t("analytics.updating")}</span>
          ) : null}
        </span>
      }
    />
  );

  if (q.error && isBlockingProblem(q.error))
    return (
      <>
        {header}
        <AnalyticsFilterBar state={filters} />
        <ProblemState error={q.error} onResetFilters={() => filters.reset()} />
      </>
    );

  return (
    <>
      {header}
      <AnalyticsFilterBar state={filters} onExport={onExport} />
      {q.error ? <ProblemState error={q.error} onRetry={() => void q.refetch()} /> : null}

      <section aria-label={t("home.kpiRow")} data-testid="kpi-row">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4 2xl:grid-cols-7">
          {data
            ? data.kpis.map((k) => <KpiTile key={k.key} kpi={k} />)
            : Array.from({ length: 7 }, (_, i) => <KpiCard key={i} title="" value="" loading />)}
        </div>
      </section>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Section title={t("home.revenueTrend")} className="xl:col-span-2" testId="revenue-trend">
          {data ? <RevenueCharts data={data} /> : <SectionSkeleton />}
        </Section>
        <Section title={t("home.ownBrandDonut")} testId="own-brand-donut">
          {data ? <OwnBrand data={data} /> : <SectionSkeleton height="h-44" />}
        </Section>
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Section title={t("home.storeMap")} className="xl:col-span-2" testId="store-map-section">
          {data ? (
            data.stores.length === 0 ? (
              <EmptyState title={t("home.noStoresTitle")} help={t("home.noStoresHelp")} />
            ) : (
              <>
                <StoreMap
                  stores={data.stores}
                  describe={(s) =>
                    t("home.storeTooltip", {
                      name: s.name,
                      revenue: formatInrShort(s.revenue_paise),
                      share: formatRatio(s.own_brand_share),
                      band: t(`home.band.${s.band}`),
                    })
                  }
                  onSelect={(id) => router.push(`/stores/${id}${filters.linkQuery}`)}
                  attribution={t("map.attribution")}
                  label={t("home.storeMap")}
                />
                <BandLegend />
                <StoreTable stores={data.stores} linkQuery={filters.linkQuery} />
              </>
            )
          ) : (
            <SectionSkeleton height="h-80" />
          )}
        </Section>
        <Section title={t("home.creditAgeing")} testId="credit-ageing">
          {data ? (
            <BarCompare
              label={t("home.creditAgeing")}
              data={OVERDUE_BUCKETS.map((b) => ({
                bucket: t(`buckets.${b}`),
                value: data.credit_overdue_buckets[b] ?? 0,
              }))}
              categoryKey="bucket"
              layout="horizontal"
              series={[{ key: "value", label: t("kpis.creditOverdue"), color: CHART.bad }]}
              valueFormat={formatInrShort}
              height={220}
            />
          ) : (
            <SectionSkeleton />
          )}
        </Section>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title={t("home.topOfficers")} testId="officers-top">
          {data ? (
            <OfficerList
              rows={data.officers_top}
              storeName={opts.storeName}
              linkQuery={filters.linkQuery}
            />
          ) : (
            <SectionSkeleton height="h-40" />
          )}
        </Section>
        <Section title={t("home.bottomOfficers")} testId="officers-bottom">
          {data ? (
            <OfficerList
              rows={data.officers_bottom}
              storeName={opts.storeName}
              linkQuery={filters.linkQuery}
            />
          ) : (
            <SectionSkeleton height="h-40" />
          )}
        </Section>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title={t("home.highFlags")} testId="high-flags">
          {data ? (
            data.high_severity_flags.length === 0 ? (
              <EmptyState title={t("home.noFlagsTitle")} help={t("home.noFlagsHelp")} />
            ) : (
              <ul className="flex flex-col divide-y divide-border">
                {data.high_severity_flags.map((f) => (
                  <li key={f.id}>
                    <Link
                      href={`/flags/${f.id}`}
                      className="flex items-start gap-3 py-2 hover:bg-background"
                      data-testid="high-flag"
                    >
                      <AlertTriangle
                        className="mt-0.5 size-4 shrink-0 text-danger"
                        aria-hidden="true"
                      />
                      <span className="flex min-w-0 flex-1 flex-col">
                        <span className="truncate text-body text-text">{f.title}</span>
                        <span className="text-small text-text-muted">
                          {f.rule} · {formatDateTimeIst(f.opened_at)}
                          {f.store_id && opts.storeName(f.store_id)
                            ? ` · ${opts.storeName(f.store_id)}`
                            : ""}
                        </span>
                      </span>
                      <SeverityBadge severity={asSeverity(f.severity)} />
                    </Link>
                  </li>
                ))}
              </ul>
            )
          ) : (
            <SectionSkeleton height="h-40" />
          )}
        </Section>
        <Section title={t("home.cropHealth")} testId="crop-health">
          {data ? (
            data.crop_health_alerts.length === 0 ? (
              <EmptyState
                illustration={<Sprout className="size-6" aria-hidden="true" />}
                title={t("home.cropHealthEmptyTitle")}
                help={t("home.cropHealthEmptyHelp")}
              />
            ) : (
              <ul className="flex flex-col gap-1 text-body">
                {data.crop_health_alerts.map((a, i) => (
                  <li key={i}>{String(a.title ?? a.problem ?? "")}</li>
                ))}
              </ul>
            )
          ) : (
            <SectionSkeleton height="h-40" />
          )}
        </Section>
      </div>
    </>
  );
}

function RevenueCharts({ data }: { data: OwnerHomeOut }) {
  const t = useT();
  const ly = new Map(data.series.revenue_last_year.map((p, i) => [i, p.value]));
  const rows = data.series.revenue.map((p, i) => ({
    start: p.start,
    end: p.end,
    revenue: p.value,
    last_year: ly.get(i) ?? null,
  }));
  const share = data.series.own_brand_share.map((p) => ({
    start: p.start,
    end: p.end,
    share: p.value,
  }));
  const title = (start: string) => {
    const row = rows.find((r) => r.start === start);
    return row ? formatRange(row.start, row.end) : formatDay(start);
  };
  if (rows.every((r) => !r.revenue))
    return <EmptyState title={t("home.noSalesTitle")} help={t("home.noSalesHelp")} />;
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <div className="flex flex-col gap-1">
        <h3 className="text-small font-semibold text-text-secondary">{t("kpis.revenue")}</h3>
        <LineTrend
          label={t("home.revenueTrend")}
          data={rows}
          xKey="start"
          series={[
            { key: "revenue", label: t("home.thisPeriod"), color: CHART_SERIES[0] },
            { key: "last_year", label: t("home.lastYear"), color: CHART.reference, dashed: true },
          ]}
          yFormat={formatInrShort}
          xFormat={formatDayShort}
          titleFormat={title}
          height={220}
        />
      </div>
      <div className="flex flex-col gap-1">
        <h3 className="text-small font-semibold text-text-secondary">{t("kpis.ownBrandShare")}</h3>
        <LineTrend
          label={t("kpis.ownBrandShare")}
          data={share}
          xKey="start"
          series={[{ key: "share", label: t("kpis.ownBrandShare"), color: CHART.ownBrand }]}
          yFormat={(v) => formatRatio(v, 0)}
          xFormat={formatDayShort}
          titleFormat={title}
          height={220}
          yDomain={[0, "auto"]}
        />
      </div>
    </div>
  );
}

function OwnBrand({ data }: { data: OwnerHomeOut }) {
  const t = useT();
  const kpi = data.kpis.find((k) => k.key === "own_brand_share");
  const revenue = data.kpis.find((k) => k.key === "revenue")?.value ?? 0;
  if (!kpi || kpi.value === null)
    return <EmptyState title={t("home.noSalesTitle")} help={t("home.noSalesHelp")} />;
  const own = Math.round((revenue ?? 0) * kpi.value);
  return (
    <ShareDonut
      label={t("home.ownBrandDonut")}
      share={kpi.value}
      ownLabel={t("brand.own")}
      otherLabel={t("brand.multi")}
      ownValue={formatInrShort(own)}
      otherValue={formatInrShort((revenue ?? 0) - own)}
      centerValue={formatRatio(kpi.value, 0)}
      centerLabel={t("brand.own")}
    />
  );
}

function BandLegend() {
  const t = useT();
  const bands = [
    { band: "green", variant: "success" },
    { band: "amber", variant: "warning" },
    { band: "red", variant: "danger" },
    { band: "none", variant: "neutral" },
  ] as const;
  return (
    <ul className="flex flex-wrap gap-2" aria-label={t("home.bandLegend")}>
      {bands.map((b) => (
        <li key={b.band}>
          <Badge variant={b.variant}>{t(`home.band.${b.band}`)}</Badge>
        </li>
      ))}
    </ul>
  );
}

function StoreTable({ stores, linkQuery }: { stores: StoreMapItem[]; linkQuery: string }) {
  const t = useT();
  const router = useRouter();
  const columns: DataTableColumn<StoreMapItem>[] = [
    { id: "name", header: t("stores.columns.store"), accessor: (s) => s.name, sortable: true },
    {
      id: "revenue",
      header: t("home.storeTable.revenue"),
      accessor: (s) => s.revenue_paise,
      cell: (s) => formatInrShort(s.revenue_paise),
      numeric: true,
      sortable: true,
    },
    {
      id: "share",
      header: t("home.storeTable.ownBrandShare"),
      accessor: (s) => s.own_brand_share,
      cell: (s) => formatRatio(s.own_brand_share),
      numeric: true,
      sortable: true,
    },
    {
      id: "score",
      header: t("home.storeTable.score"),
      accessor: (s) => s.score,
      cell: (s) => (
        <span className="inline-flex items-center gap-2">
          {s.score ?? "—"}
          <Badge
            variant={
              s.band === "green"
                ? "success"
                : s.band === "amber"
                  ? "warning"
                  : s.band === "red"
                    ? "danger"
                    : "neutral"
            }
          >
            {t(`home.band.${s.band}`)}
          </Badge>
        </span>
      ),
      numeric: true,
      sortable: true,
    },
  ];
  return (
    <details className="group">
      <summary className="cursor-pointer text-small font-semibold text-primary">
        {t("home.showStoreTable")}
      </summary>
      <DataTable
        className="mt-2"
        caption={t("home.storeMap")}
        columns={columns}
        rows={stores}
        rowKey={(s) => s.id}
        onRowClick={(s) => router.push(`/stores/${s.id}${linkQuery}`)}
      />
    </details>
  );
}

function OfficerList({
  rows,
  storeName,
  linkQuery,
}: {
  rows: OfficerRankOut[];
  storeName: (id: string | null) => string | undefined;
  linkQuery: string;
}) {
  const t = useT();
  if (rows.length === 0)
    return <EmptyState title={t("fieldTeam.emptyTitle")} help={t("fieldTeam.emptyHelp")} />;
  return (
    <ol className="flex flex-col divide-y divide-border">
      {rows.map((o) => (
        <li key={o.id}>
          <Link
            href={`/field-team/${o.id}${linkQuery}`}
            className="flex items-center gap-3 py-2 hover:bg-background"
            data-testid="officer-rank"
          >
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="truncate text-body text-text">{o.name}</span>
              <span className="text-small text-text-muted">{storeName(o.store_id) ?? ""}</span>
            </span>
            <span className="tnum text-right">
              <span className="block text-body font-semibold text-text">
                {formatDecimal(o.verified_visits_per_day, 1)}
              </span>
              <span className="text-small text-text-muted">
                {t("home.perDutyDay", { visits: o.verified_visits, days: o.duty_days })}
              </span>
            </span>
          </Link>
        </li>
      ))}
    </ol>
  );
}
