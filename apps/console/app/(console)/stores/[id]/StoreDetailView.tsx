"use client";

/**
 * C41 Store detail (WC-004 acceptance "Store P&L view by month"; AN-005): sales by category and
 * own-brand vs multi-brand (bars), margin, stock value / turns / stockouts, credit book ageing
 * (bars by bucket), day-close variance history, and the P&L by month for the 12 months ending
 * at the filter's end date (second request in parallel), with the operating-expenses note.
 */
import * as React from "react";
import { AlertTriangle } from "lucide-react";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { EmptyState } from "@/components/ds/EmptyState";
import { StatTile } from "@/components/ds/StatTile";
import { AnalyticsFilterBar } from "@/components/analytics/AnalyticsFilterBar";
import { BarCompare, CHART, CHART_SERIES } from "@/components/analytics/charts";
import { InfoTip } from "@/components/analytics/InfoTip";
import { AnalyticsGate, PageHeader, Section, SectionSkeleton } from "@/components/analytics/Page";
import { ProblemState } from "@/components/analytics/ProblemState";
import { Badge } from "@/components/ui/badge";
import { OVERDUE_BUCKETS, type PnlMonth, type StoreDetailOut } from "@/lib/analytics";
import {
  formatDay,
  formatDayShort,
  formatDecimal,
  formatInrOrDash,
  formatInrShort,
  formatMonth,
  formatRange,
  formatRatio,
} from "@/lib/analytics-format";
import { csvFilename, downloadCsv, paiseToRupees, type CsvColumn } from "@/lib/csv";
import { pnlWindow, useStoreDetail, useStorePnl } from "@/lib/hooks/analytics";
import { useAnalyticsFilters } from "@/lib/hooks/use-analytics-filters";
import type { MessageKey } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";
import { VARIANCE_THRESHOLD_PAISE } from "../StoresView";

export function StoreDetailView({ id }: { id: string }) {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C41">
      <AnalyticsGate path="/stores" title={t("storeDetail.title")}>
        <StoreDetail id={id} />
      </AnalyticsGate>
    </div>
  );
}

const CATEGORY_KEYS = [
  "seed",
  "fertiliser",
  "pesticide",
  "fungicide",
  "herbicide",
  "growth",
  "tool",
  "other",
] as const;
const categoryKey = (c: string): MessageKey =>
  `categories.${(CATEGORY_KEYS as readonly string[]).includes(c) ? (c as (typeof CATEGORY_KEYS)[number]) : "other"}`;

type DayClose = StoreDetailOut["day_closes"][number];

function StoreDetail({ id }: { id: string }) {
  const t = useT();
  const filters = useAnalyticsFilters();
  // The path names the store: a store / cluster filter from the list does not apply here.
  const apiFilters = React.useMemo(
    () => ({ ...filters.apiFilters, store_id: undefined, cluster_id: undefined }),
    [filters.apiFilters],
  );
  const q = useStoreDetail(id, apiFilters);
  const pnl = useStorePnl(id, apiFilters);
  const data = q.data;
  const back = { href: `/stores${filters.linkQuery}`, label: t("stores.backToList") };
  const pnlRange = pnlWindow(filters.filters.to);

  if (q.error)
    return (
      <>
        <PageHeader title={t("storeDetail.title")} back={back} />
        <ProblemState
          error={q.error}
          onRetry={() => void q.refetch()}
          onResetFilters={() => filters.reset()}
        />
      </>
    );

  const pnlColumns: CsvColumn<PnlMonth>[] = [
    { header: t("storeDetail.pnl.month"), value: (m) => formatMonth(m.month) },
    { header: t("storeDetail.pnl.grossSales"), value: (m) => paiseToRupees(m.gross_sales_paise) },
    { header: t("storeDetail.pnl.discounts"), value: (m) => paiseToRupees(m.discounts_paise) },
    { header: t("storeDetail.pnl.netSales"), value: (m) => paiseToRupees(m.net_sales_paise) },
    { header: t("storeDetail.pnl.cogs"), value: (m) => paiseToRupees(m.cogs_paise) },
    { header: t("storeDetail.pnl.grossMargin"), value: (m) => paiseToRupees(m.gross_margin_paise) },
    { header: t("storeDetail.pnl.marginPct"), value: (m) => m.gross_margin_pct },
    { header: t("storeDetail.pnl.writeOffs"), value: (m) => paiseToRupees(m.write_offs_paise) },
    {
      header: t("storeDetail.pnl.contribution"),
      value: (m) => paiseToRupees(m.contribution_paise),
    },
    {
      header: t("storeDetail.pnl.partial"),
      value: (m) => (m.partial ? t("common.yes") : t("common.no")),
    },
  ];

  return (
    <>
      <PageHeader
        title={data ? data.name : t("storeDetail.title")}
        back={back}
        subtitle={
          data ? (
            <span className="flex flex-wrap items-center gap-3">
              <span>
                {data.code} · {data.district}
              </span>
              <span className="tnum">{formatRange(filters.filters.from, filters.filters.to)}</span>
            </span>
          ) : undefined
        }
      />
      <AnalyticsFilterBar
        state={filters}
        hide={{ store: true, cluster: true }}
        onExport={
          pnl.data
            ? () =>
                downloadCsv(
                  csvFilename(`pnl-${pnl.data!.code}`, pnlRange.from, pnlRange.to),
                  pnlColumns,
                  pnl.data!.pnl,
                )
            : undefined
        }
      />

      <section
        aria-label={t("storeDetail.summary")}
        className="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-7"
        data-testid="store-summary"
      >
        {data ? (
          <>
            <StatTile
              label={t("stores.columns.netSales")}
              value={formatInrShort(data.net_sales_paise)}
            />
            <StatTile label={t("storeDetail.cogs")} value={formatInrShort(data.cogs_paise)} />
            <StatTile
              label={t("stores.columns.grossMargin")}
              value={formatInrShort(data.gross_margin_paise)}
            />
            <StatTile
              label={t("stores.columns.marginPct")}
              value={formatRatio(data.gross_margin_pct)}
            />
            <StatTile
              label={t("stores.columns.ownBrandShare")}
              value={formatRatio(data.brand_split.own_brand_share)}
            />
            <StatTile
              label={t("stores.columns.stockValue")}
              value={formatInrShort(data.stock.value_paise)}
            />
            <StatTile
              label={t("storeDetail.turnsAnnualised")}
              value={formatDecimal(data.stock.turns_annualised, 1)}
            />
          </>
        ) : (
          Array.from({ length: 7 }, (_, i) => <StatTile key={i} label="" value="" loading />)
        )}
      </section>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Section title={t("storeDetail.salesByCategory")} testId="sales-by-category">
          {data ? (
            data.sales_by_category.length ? (
              <BarCompare
                label={t("storeDetail.salesByCategory")}
                data={data.sales_by_category.map((c) => ({
                  category: t(categoryKey(c.category)),
                  sales: c.net_sales_paise,
                  margin: c.gross_margin_paise,
                }))}
                categoryKey="category"
                layout="horizontal"
                series={[
                  { key: "sales", label: t("stores.columns.netSales"), color: CHART_SERIES[0] },
                  { key: "margin", label: t("stores.columns.grossMargin"), color: CHART.reference },
                ]}
                valueFormat={formatInrShort}
                height={Math.max(220, data.sales_by_category.length * 40)}
              />
            ) : (
              <EmptyState
                title={t("storeDetail.noSalesTitle")}
                help={t("storeDetail.noSalesHelp")}
              />
            )
          ) : (
            <SectionSkeleton />
          )}
        </Section>
        <Section
          title={t("storeDetail.brandSplit")}
          testId="brand-split"
          info={
            <InfoTip name={t("kpiNames.ownBrandShare")} text={t("kpiDefinitions.ownBrandShare")} />
          }
        >
          {data ? (
            <BarCompare
              label={t("storeDetail.brandSplit")}
              data={[
                {
                  brand: t("brand.own"),
                  sales: data.brand_split.own_brand_paise,
                  margin: data.brand_split.own_brand_margin_paise,
                },
                {
                  brand: t("brand.multi"),
                  sales: data.brand_split.multi_brand_paise,
                  margin: data.brand_split.multi_brand_margin_paise,
                },
              ]}
              categoryKey="brand"
              series={[
                { key: "sales", label: t("stores.columns.netSales"), color: CHART.ownBrand },
                { key: "margin", label: t("stores.columns.grossMargin"), color: CHART.reference },
              ]}
              valueFormat={formatInrShort}
              height={220}
            />
          ) : (
            <SectionSkeleton />
          )}
        </Section>
      </div>

      <Section title={t("storeDetail.salesByBrand")} testId="sales-by-brand">
        {data ? (
          data.sales_by_brand.length ? (
            <BarCompare
              label={t("storeDetail.salesByBrand")}
              data={data.sales_by_brand.map((b) => ({
                brand: b.own_brand ? `${b.brand} (${t("brand.own")})` : b.brand,
                own: b.own_brand ? 1 : 0,
                sales: b.net_sales_paise,
                margin: b.gross_margin_paise,
              }))}
              categoryKey="brand"
              layout="horizontal"
              series={[
                { key: "sales", label: t("stores.columns.netSales"), color: CHART_SERIES[0] },
                { key: "margin", label: t("stores.columns.grossMargin"), color: CHART.reference },
              ]}
              colorFor={(r) => (r.own ? CHART.ownBrand : CHART_SERIES[0])}
              valueFormat={formatInrShort}
              height={Math.max(220, data.sales_by_brand.length * 40)}
            />
          ) : (
            <EmptyState title={t("storeDetail.noSalesTitle")} help={t("storeDetail.noSalesHelp")} />
          )
        ) : (
          <SectionSkeleton />
        )}
      </Section>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Section
          title={t("storeDetail.creditAgeing")}
          testId="credit-ageing"
          info={
            <InfoTip name={t("kpiNames.creditOverdue")} text={t("kpiDefinitions.creditOverdue")} />
          }
        >
          {data ? (
            <>
              <p className="text-small text-text-secondary">
                {t("storeDetail.creditSummary", {
                  outstanding: formatInrShort(data.credit_book.outstanding_paise),
                  overdue: formatInrShort(data.credit_book.overdue_paise),
                  accounts: data.credit_book.accounts,
                })}
              </p>
              <BarCompare
                label={t("storeDetail.creditAgeing")}
                data={OVERDUE_BUCKETS.map((b) => ({
                  bucket: t(`buckets.${b}`),
                  value: data.credit_book.buckets[b] ?? 0,
                }))}
                categoryKey="bucket"
                layout="horizontal"
                series={[{ key: "value", label: t("kpis.creditOverdue"), color: CHART.bad }]}
                valueFormat={formatInrShort}
                height={200}
              />
            </>
          ) : (
            <SectionSkeleton />
          )}
        </Section>
        <Section title={t("storeDetail.stock")} testId="stock">
          {data ? (
            <div className="flex flex-col gap-3">
              <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-small">
                <dt className="text-text-muted">{t("storeDetail.stockValue")}</dt>
                <dd className="tnum text-right">{formatInrOrDash(data.stock.value_paise)}</dd>
                <dt className="text-text-muted">{t("storeDetail.skusInStock")}</dt>
                <dd className="tnum text-right">{data.stock.skus_in_stock}</dd>
                <dt className="text-text-muted">{t("storeDetail.turns")}</dt>
                <dd className="tnum text-right">{formatDecimal(data.stock.turns, 2)}</dd>
                <dt className="text-text-muted">{t("storeDetail.turnsAnnualised")}</dt>
                <dd className="tnum text-right">{formatDecimal(data.stock.turns_annualised, 1)}</dd>
                <dt className="text-text-muted">{t("storeDetail.stockoutDays")}</dt>
                <dd className="tnum text-right" data-testid="stockout-days">
                  {data.stock.stockout_days}
                </dd>
              </dl>
              <h3 className="text-small font-semibold text-text-secondary">
                {t("storeDetail.stockouts", { n: data.stock.stockouts.length })}
              </h3>
              {data.stock.stockouts.length ? (
                <ul className="flex flex-col gap-1 text-small" data-testid="stockouts">
                  {data.stock.stockouts.map((s) => (
                    <li key={s.sku_id} className="flex items-start gap-2">
                      <AlertTriangle
                        className={cn(
                          "mt-0.5 size-4 shrink-0",
                          s.currently_out ? "text-danger" : "text-warning",
                        )}
                        aria-hidden="true"
                      />
                      <span className="flex flex-col">
                        <span>
                          {s.product_name} · {s.pack}
                        </span>
                        <span className="tnum text-text-muted">
                          {t(
                            s.currently_out
                              ? "storeDetail.stockoutNowDays"
                              : "storeDetail.stockoutPastDays",
                            { n: s.days_out_of_stock },
                          )}
                        </span>
                      </span>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-small text-text-muted">{t("storeDetail.noStockouts")}</p>
              )}
            </div>
          ) : (
            <SectionSkeleton />
          )}
        </Section>
        <Section title={t("storeDetail.dayCloses")} testId="day-closes">
          {data ? (
            data.day_closes.length ? (
              <BarCompare
                label={t("storeDetail.dayCloses")}
                data={[...data.day_closes].reverse().map((d) => ({
                  day: d.business_date,
                  variance: d.variance_paise,
                  flagged: d.variance_flagged ? 1 : 0,
                }))}
                categoryKey="day"
                categoryFormat={formatDayShort}
                series={[
                  { key: "variance", label: t("storeDetail.variance"), color: CHART.reference },
                ]}
                colorFor={(r) => (r.flagged ? CHART.bad : CHART.reference)}
                valueFormat={formatInrShort}
                height={200}
              />
            ) : (
              <EmptyState
                title={t("storeDetail.noDayClosesTitle")}
                help={t("storeDetail.noDayClosesHelp")}
              />
            )
          ) : (
            <SectionSkeleton />
          )}
        </Section>
      </div>

      {data?.day_closes.length ? <DayCloseTable rows={data.day_closes} /> : null}

      <Section
        title={t("storeDetail.pnl.title")}
        testId="pnl"
        actions={
          <span className="tnum text-small text-text-muted">
            {t("storeDetail.pnl.window", { range: formatRange(pnlRange.from, pnlRange.to) })}
          </span>
        }
      >
        {pnl.error ? (
          <ProblemState error={pnl.error} onRetry={() => void pnl.refetch()} />
        ) : pnl.data ? (
          <PnlTable months={pnl.data.pnl} />
        ) : (
          <SectionSkeleton height="h-72" />
        )}
        <p className="text-small text-text-secondary" data-testid="pnl-note">
          {t("storeDetail.pnl.opexNote")}
        </p>
      </Section>
    </>
  );
}

function DayCloseTable({ rows }: { rows: DayClose[] }) {
  const t = useT();
  const columns: DataTableColumn<DayClose>[] = [
    {
      id: "day",
      header: t("storeDetail.dayClose.date"),
      accessor: (d) => d.business_date,
      cell: (d) => formatDay(d.business_date),
      sortable: true,
    },
    {
      id: "expected",
      header: t("storeDetail.dayClose.expected"),
      numeric: true,
      cell: (d) => formatInrOrDash(d.cash_expected_paise),
    },
    {
      id: "counted",
      header: t("storeDetail.dayClose.counted"),
      numeric: true,
      cell: (d) => formatInrOrDash(d.cash_counted_paise),
    },
    {
      id: "variance",
      header: t("storeDetail.variance"),
      numeric: true,
      accessor: (d) => d.variance_paise,
      sortable: true,
      cell: (d) => (
        <span
          className={cn(
            "inline-flex items-center gap-2",
            Math.abs(d.variance_paise) > VARIANCE_THRESHOLD_PAISE && "font-semibold text-danger",
          )}
        >
          {formatInrOrDash(d.variance_paise)}
          {d.variance_flagged ? (
            <Badge variant="danger">{t("storeDetail.dayClose.flagged")}</Badge>
          ) : null}
        </span>
      ),
    },
    {
      id: "status",
      header: t("storeDetail.dayClose.status"),
      cell: (d) => (d.status === "closed" ? t("storeDetail.dayClose.closed") : d.status),
    },
  ];
  return (
    <details>
      <summary className="cursor-pointer text-small font-semibold text-primary">
        {t("storeDetail.dayClose.showTable")}
      </summary>
      <DataTable
        className="mt-2"
        caption={t("storeDetail.dayCloses")}
        columns={columns}
        rows={rows}
        rowKey={(d) => d.business_date}
      />
    </details>
  );
}

function PnlTable({ months }: { months: PnlMonth[] }) {
  const t = useT();
  if (months.length === 0)
    return <EmptyState title={t("storeDetail.noSalesTitle")} help={t("storeDetail.noSalesHelp")} />;
  const lines: Array<{
    key: keyof PnlMonth;
    label: string;
    strong?: boolean;
    negative?: boolean;
    pct?: boolean;
  }> = [
    { key: "gross_sales_paise", label: t("storeDetail.pnl.grossSales") },
    { key: "discounts_paise", label: t("storeDetail.pnl.discounts"), negative: true },
    { key: "net_sales_paise", label: t("storeDetail.pnl.netSales"), strong: true },
    { key: "cogs_paise", label: t("storeDetail.pnl.cogs"), negative: true },
    { key: "gross_margin_paise", label: t("storeDetail.pnl.grossMargin"), strong: true },
    { key: "gross_margin_pct", label: t("storeDetail.pnl.marginPct"), pct: true },
    { key: "write_offs_paise", label: t("storeDetail.pnl.writeOffs"), negative: true },
    { key: "contribution_paise", label: t("storeDetail.pnl.contribution"), strong: true },
  ];
  return (
    <div className="overflow-x-auto rounded-card border border-border" data-testid="pnl-table">
      <table className="w-full min-w-[720px] text-small">
        <caption className="sr-only">{t("storeDetail.pnl.title")}</caption>
        <thead>
          <tr className="border-b border-border bg-background">
            <th scope="col" className="px-3 py-2 text-left font-semibold text-text-secondary">
              {t("storeDetail.pnl.line")}
            </th>
            {months.map((m) => (
              <th
                key={m.month}
                scope="col"
                className="px-3 py-2 text-right font-semibold text-text-secondary"
              >
                {formatMonth(m.month)}
                {m.partial ? (
                  <span className="block font-regular text-text-muted">
                    {t("storeDetail.pnl.partialShort")}
                  </span>
                ) : null}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {lines.map((line) => (
            <tr
              key={line.key}
              className={cn(
                "border-b border-border last:border-0",
                line.strong && "bg-background/60",
              )}
            >
              <th
                scope="row"
                className={cn(
                  "px-3 py-2 text-left text-text",
                  line.strong ? "font-semibold" : "font-regular",
                )}
              >
                {line.label}
              </th>
              {months.map((m) => {
                const v = m[line.key] as number | null;
                return (
                  <td
                    key={m.month}
                    className={cn(
                      "tnum px-3 py-2 text-right",
                      line.strong && "font-semibold",
                      v !== null && v < 0 && "text-danger",
                    )}
                  >
                    {line.pct
                      ? formatRatio(v)
                      : v === null
                        ? "—"
                        : `${line.negative && v > 0 ? "−" : ""}${formatInrShort(v)}`}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
