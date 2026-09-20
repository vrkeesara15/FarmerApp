"use client";

/**
 * C30 Farmers directory (WC-003 / AN-004 list): search (name, last 4 phone digits, village),
 * filters (crop via AN-011, district, stage, credit risk, last-visit window), server-side sort
 * and cursor pagination ("Load more"). Every choice lives in the URL. Phones are masked
 * (AN-014); the full number is only on the audited 360 view. Row -> C31.
 */
import * as React from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Users } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn, type DataTableSort } from "@/components/ds/DataTable";
import { SearchBar } from "@/components/ds/SearchBar";
import { AnalyticsFilterBar } from "@/components/analytics/AnalyticsFilterBar";
import { LinkButton } from "@/components/growth/common";
import { Definitions } from "@/components/analytics/Definitions";
import { AnalyticsGate, PageHeader, ScopeNote } from "@/components/analytics/Page";
import { isBlockingProblem, ProblemState } from "@/components/analytics/ProblemState";
import { Badge } from "@/components/ui/badge";
import { SelectField } from "@/app/(console)/products/_components/fields";
import {
  CREDIT_RISKS,
  CROP_STAGES,
  FARMER_SORTS,
  LAST_VISIT_WINDOWS,
  type CreditRisk,
  type FarmerRow,
} from "@/lib/analytics";
import { formatDecimal, formatInrShort, formatRange, stageLabel } from "@/lib/analytics-format";
import { csvFilename, downloadCsv, paiseToRupees, type CsvColumn } from "@/lib/csv";
import { formatDateIst } from "@/lib/format";
import { useFarmerDirectory, useFilterOptions } from "@/lib/hooks/analytics";
import {
  useAnalyticsFilters,
  useSearchParam,
  useSetSearchParams,
} from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";

export function FarmersView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C30">
      <AnalyticsGate path="/farmers" title={t("farmers.title")}>
        <Farmers />
      </AnalyticsGate>
    </div>
  );
}

const RISK_VARIANT: Record<CreditRisk, "success" | "warning" | "danger"> = {
  low: "success",
  medium: "warning",
  high: "danger",
};

/** Column id -> API sort key. */
const SORT_BY_COLUMN: Record<string, string> = {
  name: "name",
  lastVisit: "last_visit",
  lastPurchase: "last_purchase",
  balance: "balance",
  overdue: "overdue",
  ltv: "ltv",
};

const valid = <T extends string>(list: readonly T[], v: string | undefined): T | undefined =>
  v && (list as readonly string[]).includes(v) ? (v as T) : undefined;

function Farmers() {
  const t = useT();
  const router = useRouter();
  const filters = useAnalyticsFilters();
  const opts = useFilterOptions();
  const [qParam, setQParam] = useSearchParam("q");
  const setParams = useSetSearchParams();
  const search = useSearchParams();
  const params = {
    district: search?.get("district") ?? undefined,
    stage: search?.get("stage") ?? undefined,
    risk: search?.get("risk") ?? undefined,
    lastVisit: search?.get("last_visit") ?? undefined,
    sort: search?.get("sort") ?? undefined,
  };
  const [text, setText] = React.useState(qParam ?? "");

  React.useEffect(() => setText(qParam ?? ""), [qParam]);
  React.useEffect(() => {
    const next = text.trim();
    if (next === (qParam ?? "")) return;
    const h = setTimeout(() => setQParam(next || undefined, { replace: true }), 350);
    return () => clearTimeout(h);
  }, [text, qParam, setQParam]);

  const stage = valid(CROP_STAGES, params.stage);
  const risk = valid(CREDIT_RISKS, params.risk);
  const lastVisit = valid(LAST_VISIT_WINDOWS, params.lastVisit);
  const sortRaw = params.sort ?? "name";
  const sortKey = valid(FARMER_SORTS, sortRaw.replace(/^-/, "")) ?? "name";
  const desc = sortRaw.startsWith("-");
  const apiSort = `${desc ? "-" : ""}${sortKey}`;

  const q = useFarmerDirectory(filters.apiFilters, {
    q: qParam || undefined,
    district: params.district || undefined,
    stage,
    credit_risk: risk,
    last_visit: lastVisit,
    sort: apiSort,
    limit: 50,
  });
  const pages = q.data?.pages ?? [];
  const rows = pages.flatMap((p) => p.items);
  const total = pages[0]?.total;
  const districts = [...new Set(opts.stores.map((s) => s.district))].sort();

  const sort: DataTableSort = {
    columnId: Object.entries(SORT_BY_COLUMN).find(([, v]) => v === sortKey)?.[0] ?? "name",
    direction: desc ? "desc" : "asc",
  };

  const columns: DataTableColumn<FarmerRow>[] = [
    {
      id: "name",
      header: t("farmers.columns.name"),
      sortable: true,
      cell: (r) => (
        <span className="flex flex-col">
          <span className="font-semibold text-text">{r.name}</span>
          <span className="tnum text-small text-text-muted">{r.phone_masked}</span>
        </span>
      ),
    },
    {
      id: "village",
      header: t("farmers.columns.village"),
      cell: (r) => (
        <span className="flex flex-col">
          <span>{r.village}</span>
          <span className="text-small text-text-muted">{r.district}</span>
        </span>
      ),
    },
    {
      id: "crops",
      header: t("farmers.columns.crops"),
      cell: (r) => (
        <span className="flex flex-wrap gap-1">
          {r.crops.map((c) => (
            <Badge key={c} variant="outline">
              {opts.crops.find((x) => x.code === c)?.name ?? c}
            </Badge>
          ))}
          {r.stages.map((s) => (
            <Badge key={s} variant="neutral">
              {stageLabel(s, t)}
            </Badge>
          ))}
        </span>
      ),
    },
    {
      id: "acres",
      header: t("farmers.columns.acres"),
      cell: (r) => formatDecimal(r.acres, 1),
      numeric: true,
    },
    {
      id: "lastVisit",
      header: t("farmers.columns.lastVisit"),
      sortable: true,
      cell: (r) => (r.last_visit_at ? formatDateIst(r.last_visit_at) : t("farmers.never")),
    },
    {
      id: "lastPurchase",
      header: t("farmers.columns.lastPurchase"),
      sortable: true,
      cell: (r) => (r.last_purchase_at ? formatDateIst(r.last_purchase_at) : t("farmers.never")),
    },
    {
      id: "balance",
      header: t("farmers.columns.balance"),
      sortable: true,
      numeric: true,
      cell: (r) => formatInrShort(r.balance_paise),
    },
    {
      id: "overdue",
      header: t("farmers.columns.overdue"),
      sortable: true,
      numeric: true,
      cell: (r) => (
        <span className="inline-flex items-center gap-2">
          {formatInrShort(r.overdue_paise)}
          <Badge variant={RISK_VARIANT[r.credit_risk]}>{t(`farmers.risk.${r.credit_risk}`)}</Badge>
        </span>
      ),
    },
    {
      id: "ltv",
      header: t("farmers.columns.ltv"),
      sortable: true,
      numeric: true,
      cell: (r) => formatInrShort(r.ltv_paise),
    },
    {
      id: "app",
      header: t("farmers.columns.app"),
      cell: (r) => (r.app_user ? t("common.yes") : t("common.no")),
    },
  ];

  const csvColumns: CsvColumn<FarmerRow>[] = [
    { header: t("farmers.columns.name"), value: (r) => r.name },
    { header: t("farmers.columns.phone"), value: (r) => r.phone_masked },
    { header: t("farmers.columns.village"), value: (r) => r.village },
    { header: t("farmers.columns.district"), value: (r) => r.district },
    { header: t("farmers.columns.crops"), value: (r) => r.crops.join(" ") },
    { header: t("farmers.columns.stage"), value: (r) => r.stages.join(" ") },
    { header: t("farmers.columns.acres"), value: (r) => r.acres },
    {
      header: t("farmers.columns.lastVisit"),
      value: (r) => (r.last_visit_at ? formatDateIst(r.last_visit_at) : ""),
    },
    {
      header: t("farmers.columns.lastPurchase"),
      value: (r) => (r.last_purchase_at ? formatDateIst(r.last_purchase_at) : ""),
    },
    { header: t("farmers.columns.balanceRupees"), value: (r) => paiseToRupees(r.balance_paise) },
    { header: t("farmers.columns.overdueRupees"), value: (r) => paiseToRupees(r.overdue_paise) },
    { header: t("farmers.columns.risk"), value: (r) => t(`farmers.risk.${r.credit_risk}`) },
    { header: t("farmers.columns.ltvRupees"), value: (r) => paiseToRupees(r.ltv_paise) },
    {
      header: t("farmers.columns.app"),
      value: (r) => (r.app_user ? t("common.yes") : t("common.no")),
    },
  ];

  const narrowed = !!(qParam || params.district || stage || risk || lastVisit);

  return (
    <>
      <PageHeader
        title={t("farmers.title")}
        subtitle={
          <span className="flex flex-wrap items-center gap-3">
            <span className="tnum">{formatRange(filters.filters.from, filters.filters.to)}</span>
            <ScopeNote scope={pages[0]?.filters.scope} />
            {total !== undefined ? (
              <span className="tnum text-small text-text-muted" data-testid="farmer-total">
                {t("farmers.total", { n: total })}
              </span>
            ) : null}
          </span>
        }
        actions={
          <LinkButton href="/farmers/segments" variant="secondary" testId="open-segments">
            <Users className="size-4" aria-hidden="true" />
            {t("farmers.segmentsLink")}
          </LinkButton>
        }
      />
      <AnalyticsFilterBar
        state={filters}
        hide={{ officer: false }}
        onExport={
          rows.length
            ? () =>
                downloadCsv(
                  csvFilename("farmers", filters.filters.from, filters.filters.to),
                  csvColumns,
                  rows,
                )
            : undefined
        }
      />
      <div
        className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3"
        data-testid="farmer-filters"
      >
        <div className="flex min-w-[260px] flex-1 flex-col gap-1">
          <label htmlFor="farmer-search" className="text-small font-semibold text-text-secondary">
            {t("common.search")}
          </label>
          <SearchBar
            id="farmer-search"
            value={text}
            onChange={setText}
            onSubmit={(v) => setQParam(v.trim() || undefined)}
            placeholder={t("farmers.searchPlaceholder")}
            label={t("farmers.searchLabel")}
            loading={q.isFetching && !q.isFetchingNextPage}
          />
        </div>
        <SelectField
          className="w-44"
          label={t("farmers.filters.district")}
          value={params.district ?? ""}
          emptyLabel={t("common.all")}
          options={districts.map((d) => ({ value: d, label: d }))}
          onChange={(e) => setParams({ district: e.target.value || undefined })}
        />
        <SelectField
          className="w-40"
          label={t("farmers.filters.stage")}
          value={stage ?? ""}
          emptyLabel={t("common.all")}
          options={CROP_STAGES.map((s) => ({ value: s, label: t(`stage.${s}`) }))}
          onChange={(e) => setParams({ stage: e.target.value || undefined })}
        />
        <SelectField
          className="w-40"
          label={t("farmers.filters.risk")}
          value={risk ?? ""}
          emptyLabel={t("common.all")}
          options={CREDIT_RISKS.map((r) => ({ value: r, label: t(`farmers.risk.${r}`) }))}
          onChange={(e) => setParams({ risk: e.target.value || undefined })}
        />
        <SelectField
          className="w-48"
          label={t("farmers.filters.lastVisit")}
          value={lastVisit ?? ""}
          emptyLabel={t("common.all")}
          options={LAST_VISIT_WINDOWS.map((w) => ({
            value: w,
            label: t(`farmers.lastVisitWindow.${w}`),
          }))}
          onChange={(e) => setParams({ last_visit: e.target.value || undefined })}
        />
        {narrowed ? (
          <AppButton
            variant="tertiary"
            size="M"
            onClick={() => {
              setText("");
              setParams({
                q: undefined,
                district: undefined,
                stage: undefined,
                risk: undefined,
                last_visit: undefined,
              });
            }}
          >
            {t("common.clear")}
          </AppButton>
        ) : null}
      </div>
      <Definitions keys={["creditOverdue", "ltv", "activeFarmer"]} />
      {q.error && isBlockingProblem(q.error) ? (
        <ProblemState error={q.error} onResetFilters={() => filters.reset()} />
      ) : (
        <div className="flex flex-col gap-3">
          <div className="overflow-x-auto">
            <DataTable
              caption={t("farmers.title")}
              columns={columns}
              rows={rows}
              rowKey={(r) => r.id}
              sort={sort}
              onSortChange={(s) =>
                setParams({
                  sort: `${s.direction === "desc" ? "-" : ""}${SORT_BY_COLUMN[s.columnId] ?? "name"}`,
                })
              }
              loading={q.isLoading}
              error={q.error ? t("analytics.errorTitle") : undefined}
              onRetry={() => void q.refetch()}
              emptyTitle={narrowed ? t("farmers.emptyFilteredTitle") : t("farmers.emptyTitle")}
              emptyHelp={narrowed ? t("farmers.emptyFilteredHelp") : t("farmers.emptyHelp")}
              onRowClick={(r) => router.push(`/farmers/${r.id}${filters.linkQuery}`)}
            />
          </div>
          {q.hasNextPage ? (
            <AppButton
              variant="secondary"
              className="self-center"
              onClick={() => void q.fetchNextPage()}
              loading={q.isFetchingNextPage}
              data-testid="load-more"
            >
              {t("farmers.loadMore", { shown: rows.length, total: total ?? rows.length })}
            </AppButton>
          ) : null}
        </div>
      )}
    </>
  );
}
