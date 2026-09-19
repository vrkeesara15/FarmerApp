"use client";

/** C20 Field team scorecard (WC-002 / AN-002): ranked, sortable, weekly sparklines; row -> C21. */
import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { AnalyticsFilterBar } from "@/components/analytics/AnalyticsFilterBar";
import { Sparkline } from "@/components/analytics/charts";
import { Definitions } from "@/components/analytics/Definitions";
import { AnalyticsGate, PageHeader, ScopeNote } from "@/components/analytics/Page";
import { isBlockingProblem, ProblemState } from "@/components/analytics/ProblemState";
import type { ScorecardRow } from "@/lib/analytics";
import {
  formatCount,
  formatDecimal,
  formatInrShort,
  formatRange,
  formatRatio,
  formatSeconds,
} from "@/lib/analytics-format";
import { csvFilename, downloadCsv, paiseToRupees, type CsvColumn } from "@/lib/csv";
import { useFieldTeam, useFilterOptions } from "@/lib/hooks/analytics";
import { useAnalyticsFilters } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";

export function FieldTeamView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C20">
      <AnalyticsGate path="/field-team" title={t("fieldTeam.title")}>
        <FieldTeam />
      </AnalyticsGate>
    </div>
  );
}

function FieldTeam() {
  const t = useT();
  const router = useRouter();
  const filters = useAnalyticsFilters();
  const q = useFieldTeam(filters.apiFilters);
  const opts = useFilterOptions();
  const rows = q.data?.items ?? [];
  const locationVisible = q.data?.location_visible ?? true;

  const columns: DataTableColumn<ScorecardRow>[] = [
    {
      id: "rank",
      header: t("fieldTeam.columns.rank"),
      accessor: (r) => r.rank,
      sortable: true,
      numeric: true,
      width: "4rem",
    },
    {
      id: "name",
      header: t("fieldTeam.columns.officer"),
      accessor: (r) => r.name,
      sortable: true,
      cell: (r) => (
        <span className="flex flex-col">
          <Link
            href={`/field-team/${r.officer_id}${filters.linkQuery}`}
            className="font-semibold text-text hover:text-primary"
            onClick={(e) => e.stopPropagation()}
          >
            {r.name}
          </Link>
          <span className="text-small text-text-muted">{opts.storeName(r.store_id) ?? ""}</span>
        </span>
      ),
    },
    {
      id: "vpd",
      header: t("fieldTeam.columns.verifiedPerDay"),
      accessor: (r) => r.verified_visits_per_day,
      cell: (r) => formatDecimal(r.verified_visits_per_day, 1),
      sortable: true,
      numeric: true,
    },
    {
      id: "unique",
      header: t("fieldTeam.columns.uniqueFarmers"),
      accessor: (r) => r.unique_farmers_reached,
      sortable: true,
      numeric: true,
    },
    {
      id: "reg",
      header: t("fieldTeam.columns.newRegistrations"),
      accessor: (r) => r.new_registrations,
      sortable: true,
      numeric: true,
    },
    {
      id: "conf",
      header: t("fieldTeam.columns.confirmationRate"),
      accessor: (r) => r.confirmation_rate,
      cell: (r) => formatRatio(r.confirmation_rate),
      sortable: true,
      numeric: true,
    },
    {
      id: "tof",
      header: t("fieldTeam.columns.timeOnFarm"),
      accessor: (r) => r.avg_time_on_farm_s,
      cell: (r) => formatSeconds(r.avg_time_on_farm_s),
      sortable: true,
      numeric: true,
    },
    ...(locationVisible
      ? [
          {
            id: "km",
            header: t("fieldTeam.columns.kmPerDay"),
            accessor: (r: ScorecardRow) => r.km_per_day,
            cell: (r: ScorecardRow) => formatDecimal(r.km_per_day, 1),
            sortable: true,
            numeric: true,
          },
        ]
      : []),
    {
      id: "conv",
      header: t("fieldTeam.columns.conversion"),
      accessor: (r) => r.conversion_rate,
      cell: (r) => formatRatio(r.conversion_rate),
      sortable: true,
      numeric: true,
    },
    {
      id: "col",
      header: t("fieldTeam.columns.collections"),
      accessor: (r) => r.collections_paise,
      cell: (r) => formatInrShort(r.collections_paise),
      sortable: true,
      numeric: true,
    },
    {
      id: "flags",
      header: t("fieldTeam.columns.flags"),
      accessor: (r) => r.flags,
      sortable: true,
      numeric: true,
    },
    {
      id: "trend",
      header: t("fieldTeam.columns.trend"),
      cell: (r) => (
        <Sparkline
          values={r.trend.map((p) => p.value)}
          label={t("fieldTeam.trendLabel", {
            name: r.name,
            values: r.trend.map((p) => formatCount(p.value)).join(", "),
          })}
        />
      ),
    },
  ];

  const csvColumns: CsvColumn<ScorecardRow>[] = [
    { header: t("fieldTeam.columns.rank"), value: (r) => r.rank },
    { header: t("fieldTeam.columns.officer"), value: (r) => r.name },
    { header: t("fieldTeam.columns.store"), value: (r) => opts.storeName(r.store_id) ?? "" },
    { header: t("fieldTeam.columns.dutyDays"), value: (r) => r.duty_days },
    { header: t("fieldTeam.columns.verifiedVisits"), value: (r) => r.verified_visits },
    { header: t("fieldTeam.columns.verifiedPerDay"), value: (r) => r.verified_visits_per_day },
    { header: t("fieldTeam.columns.uniqueFarmers"), value: (r) => r.unique_farmers_reached },
    { header: t("fieldTeam.columns.newRegistrations"), value: (r) => r.new_registrations },
    { header: t("fieldTeam.columns.confirmationRate"), value: (r) => r.confirmation_rate },
    {
      header: t("fieldTeam.columns.timeOnFarmMinutes"),
      value: (r) => (r.avg_time_on_farm_s === null ? null : Math.round(r.avg_time_on_farm_s / 60)),
    },
    ...(locationVisible
      ? [{ header: t("fieldTeam.columns.kmPerDay"), value: (r: ScorecardRow) => r.km_per_day }]
      : []),
    { header: t("fieldTeam.columns.conversion"), value: (r) => r.conversion_rate },
    {
      header: t("fieldTeam.columns.collectionsRupees"),
      value: (r) => paiseToRupees(r.collections_paise),
    },
    { header: t("fieldTeam.columns.flags"), value: (r) => r.flags },
  ];

  const header = (
    <PageHeader
      title={t("fieldTeam.title")}
      subtitle={
        <span className="flex flex-wrap items-center gap-3">
          <span className="tnum">{formatRange(filters.filters.from, filters.filters.to)}</span>
          <ScopeNote scope={q.data?.filters.scope} />
          {!locationVisible ? (
            <span className="text-small text-text-muted">{t("fieldTeam.noLocation")}</span>
          ) : null}
        </span>
      }
    />
  );

  return (
    <>
      {header}
      <AnalyticsFilterBar
        state={filters}
        onExport={
          rows.length
            ? () =>
                downloadCsv(
                  csvFilename("field-team", filters.filters.from, filters.filters.to),
                  csvColumns,
                  rows,
                )
            : undefined
        }
      />
      <Definitions
        keys={["verifiedVisit", "uniqueFarmers", "confirmationRate", "timeOnFarm", "conversion"]}
      />
      {q.error && isBlockingProblem(q.error) ? (
        <ProblemState error={q.error} onResetFilters={() => filters.reset()} />
      ) : (
        <div className="overflow-x-auto">
          <DataTable
            caption={t("fieldTeam.title")}
            columns={columns}
            rows={rows}
            rowKey={(r) => r.officer_id}
            loading={q.isLoading}
            error={q.error ? t("analytics.errorTitle") : undefined}
            onRetry={() => void q.refetch()}
            emptyTitle={t("fieldTeam.emptyTitle")}
            emptyHelp={t("fieldTeam.emptyHelp")}
            onRowClick={(r) => router.push(`/field-team/${r.officer_id}${filters.linkQuery}`)}
          />
        </div>
      )}
    </>
  );
}
