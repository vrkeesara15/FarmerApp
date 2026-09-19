"use client";

/** C40 Stores list (WC-004 / AN-005): net sales comparison bars + table; row -> C41. */
import * as React from "react";
import { useRouter } from "next/navigation";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { AnalyticsFilterBar } from "@/components/analytics/AnalyticsFilterBar";
import { BarCompare, CHART, CHART_SERIES } from "@/components/analytics/charts";
import { Definitions } from "@/components/analytics/Definitions";
import {
  AnalyticsGate,
  PageHeader,
  ScopeNote,
  Section,
  SectionSkeleton,
} from "@/components/analytics/Page";
import { isBlockingProblem, ProblemState } from "@/components/analytics/ProblemState";
import type { StoreRow } from "@/lib/analytics";
import { formatDay, formatInrShort, formatRange, formatRatio } from "@/lib/analytics-format";
import { csvFilename, downloadCsv, paiseToRupees, type CsvColumn } from "@/lib/csv";
import { useStoresAnalytics } from "@/lib/hooks/analytics";
import { useAnalyticsFilters } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export function StoresView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C40">
      <AnalyticsGate path="/stores" title={t("stores.title")}>
        <Stores />
      </AnalyticsGate>
    </div>
  );
}

/** Day-close variance above ₹500 is flagged (tenant default, ST-006). */
export const VARIANCE_THRESHOLD_PAISE = 500_00;

function Stores() {
  const t = useT();
  const router = useRouter();
  const filters = useAnalyticsFilters();
  const q = useStoresAnalytics(filters.apiFilters);
  const rows = q.data?.items ?? [];

  const columns: DataTableColumn<StoreRow>[] = [
    {
      id: "name",
      header: t("stores.columns.store"),
      accessor: (s) => s.name,
      sortable: true,
      cell: (s) => (
        <span className="flex flex-col">
          <span className="font-semibold text-text">{s.name}</span>
          <span className="text-small text-text-muted">
            {s.code} · {s.district}
          </span>
        </span>
      ),
    },
    {
      id: "sales",
      header: t("stores.columns.netSales"),
      accessor: (s) => s.net_sales_paise,
      cell: (s) => formatInrShort(s.net_sales_paise),
      numeric: true,
      sortable: true,
    },
    {
      id: "margin",
      header: t("stores.columns.grossMargin"),
      accessor: (s) => s.gross_margin_paise,
      cell: (s) => formatInrShort(s.gross_margin_paise),
      numeric: true,
      sortable: true,
    },
    {
      id: "marginPct",
      header: t("stores.columns.marginPct"),
      accessor: (s) => s.gross_margin_pct,
      cell: (s) => formatRatio(s.gross_margin_pct),
      numeric: true,
      sortable: true,
    },
    {
      id: "own",
      header: t("stores.columns.ownBrandShare"),
      accessor: (s) => s.own_brand_share,
      cell: (s) => formatRatio(s.own_brand_share),
      numeric: true,
      sortable: true,
    },
    {
      id: "orders",
      header: t("stores.columns.orders"),
      accessor: (s) => s.orders,
      numeric: true,
      sortable: true,
    },
    {
      id: "stock",
      header: t("stores.columns.stockValue"),
      accessor: (s) => s.stock_value_paise,
      cell: (s) => formatInrShort(s.stock_value_paise),
      numeric: true,
      sortable: true,
    },
    {
      id: "outstanding",
      header: t("stores.columns.creditOutstanding"),
      accessor: (s) => s.credit_outstanding_paise,
      cell: (s) => formatInrShort(s.credit_outstanding_paise),
      numeric: true,
      sortable: true,
    },
    {
      id: "overdue",
      header: t("stores.columns.creditOverdue"),
      accessor: (s) => s.credit_overdue_paise,
      cell: (s) => formatInrShort(s.credit_overdue_paise),
      numeric: true,
      sortable: true,
    },
    {
      id: "variance",
      header: t("stores.columns.lastVariance"),
      accessor: (s) => s.last_day_close?.variance_paise ?? null,
      numeric: true,
      sortable: true,
      cell: (s) =>
        s.last_day_close ? (
          <span className="flex flex-col items-end">
            <span
              className={cn(
                Math.abs(s.last_day_close.variance_paise) > VARIANCE_THRESHOLD_PAISE &&
                  "font-semibold text-danger",
              )}
            >
              {formatInrShort(s.last_day_close.variance_paise)}
            </span>
            <span className="text-small text-text-muted">
              {formatDay(s.last_day_close.business_date)}
            </span>
          </span>
        ) : (
          t("stores.noDayClose")
        ),
    },
  ];

  const csvColumns: CsvColumn<StoreRow>[] = [
    { header: t("stores.columns.code"), value: (s) => s.code },
    { header: t("stores.columns.store"), value: (s) => s.name },
    { header: t("stores.columns.district"), value: (s) => s.district },
    { header: t("stores.columns.netSalesRupees"), value: (s) => paiseToRupees(s.net_sales_paise) },
    { header: t("stores.columns.cogsRupees"), value: (s) => paiseToRupees(s.cogs_paise) },
    {
      header: t("stores.columns.grossMarginRupees"),
      value: (s) => paiseToRupees(s.gross_margin_paise),
    },
    { header: t("stores.columns.marginPct"), value: (s) => s.gross_margin_pct },
    { header: t("stores.columns.ownBrandShare"), value: (s) => s.own_brand_share },
    { header: t("stores.columns.orders"), value: (s) => s.orders },
    {
      header: t("stores.columns.stockValueRupees"),
      value: (s) => paiseToRupees(s.stock_value_paise),
    },
    {
      header: t("stores.columns.creditOutstandingRupees"),
      value: (s) => paiseToRupees(s.credit_outstanding_paise),
    },
    {
      header: t("stores.columns.creditOverdueRupees"),
      value: (s) => paiseToRupees(s.credit_overdue_paise),
    },
    {
      header: t("stores.columns.lastVarianceRupees"),
      value: (s) => paiseToRupees(s.last_day_close?.variance_paise),
    },
  ];

  const chartRows = [...rows]
    .sort((a, b) => b.net_sales_paise - a.net_sales_paise)
    .map((s) => ({ name: s.name, sales: s.net_sales_paise, margin: s.gross_margin_paise }));

  return (
    <>
      <PageHeader
        title={t("stores.title")}
        subtitle={
          <span className="flex flex-wrap items-center gap-3">
            <span className="tnum">{formatRange(filters.filters.from, filters.filters.to)}</span>
            <ScopeNote scope={q.data?.filters.scope} />
          </span>
        }
      />
      <AnalyticsFilterBar
        state={filters}
        onExport={
          rows.length
            ? () =>
                downloadCsv(
                  csvFilename("stores", filters.filters.from, filters.filters.to),
                  csvColumns,
                  rows,
                )
            : undefined
        }
      />
      <Definitions keys={["ownBrandShare", "creditOverdue"]} />
      {q.error && isBlockingProblem(q.error) ? (
        <ProblemState error={q.error} onResetFilters={() => filters.reset()} />
      ) : (
        <>
          {rows.length > 1 || q.isLoading ? (
            <Section title={t("stores.salesComparison")} testId="stores-chart">
              {q.data ? (
                <BarCompare
                  label={t("stores.salesComparison")}
                  data={chartRows}
                  categoryKey="name"
                  layout="horizontal"
                  series={[
                    { key: "sales", label: t("stores.columns.netSales"), color: CHART_SERIES[0] },
                    {
                      key: "margin",
                      label: t("stores.columns.grossMargin"),
                      color: CHART.reference,
                    },
                  ]}
                  valueFormat={formatInrShort}
                  height={Math.max(220, chartRows.length * 34)}
                />
              ) : (
                <SectionSkeleton />
              )}
            </Section>
          ) : null}
          <div className="overflow-x-auto">
            <DataTable
              caption={t("stores.title")}
              columns={columns}
              rows={rows}
              rowKey={(s) => s.id}
              loading={q.isLoading}
              error={q.error ? t("analytics.errorTitle") : undefined}
              onRetry={() => void q.refetch()}
              emptyTitle={t("stores.emptyTitle")}
              emptyHelp={t("stores.emptyHelp")}
              onRowClick={(s) => router.push(`/stores/${s.id}${filters.linkQuery}`)}
            />
          </div>
        </>
      )}
    </>
  );
}
