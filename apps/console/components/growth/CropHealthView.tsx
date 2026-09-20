"use client";

/**
 * AN-006 crop health map. `GET /v1/analytics/crop-health?weeks=&district=&crop_id=` returns one
 * cell per district x crop x problem x ISO week with the four-week baseline and the outbreak
 * flag; the screen shows the chosen week on a graduated district map, lists the outbreak flags
 * and drills into one district's problems. AN-014: district level only — no farm locations.
 *
 * Crop and week live in the URL (AN-011), so a link carries the view.
 */
import * as React from "react";
import { AlertTriangle, MapPin } from "lucide-react";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Skeleton } from "@/components/ds/Skeleton";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/analytics/Page";
import { QueryError, RoleGate, SessionGate } from "@/components/admin/common";
import { CropHealthMap } from "@/components/analytics/maps";
import { formatDateIst, formatNumber } from "@/lib/format";
import { useCropHealth } from "@/lib/hooks/mlops";
import { useFilterOptions } from "@/lib/hooks/analytics";
import { useSearchParam } from "@/lib/hooks/use-analytics-filters";
import {
  QUALITY_ROLES,
  outbreakCells,
  rollupByDistrict,
  weekKeyOf,
  weekKeys,
  type CropHealthCell,
  type DistrictRollup,
} from "@/lib/mlops";
import { useLocale, useT } from "@/lib/i18n-client";
import { Choice, Note } from "./common";

const WEEK_OPTIONS = [4, 8, 13, 26] as const;

export function CropHealthView() {
  return (
    <div className="flex flex-col gap-4" data-screen="AN-006">
      <SessionGate>
        <RoleGate roles={QUALITY_ROLES}>
          <CropHealth />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function CropHealth() {
  const t = useT();
  const locale = useLocale();
  const opts = useFilterOptions();
  const [cropParam, setCrop] = useSearchParam("crop");
  const [weekParam, setWeek] = useSearchParam("week");
  const [weeksParam, setWeeks] = useSearchParam("weeks");
  const [district, setDistrict] = useSearchParam("district");
  const weeks = Number(weeksParam) > 0 ? Number(weeksParam) : 8;

  const health = useCropHealth({ weeks, crop_id: cropParam || undefined });
  const items = React.useMemo(() => health.data?.items ?? [], [health.data]);
  const available = React.useMemo(() => weekKeys(items), [items]);
  const week = weekParam && available.includes(weekParam) ? weekParam : available[0];
  const districts = React.useMemo(() => rollupByDistrict(items, week), [items, week]);
  const outbreaks = React.useMemo(
    () => outbreakCells(items).filter((c) => !week || weekKeyOf(c) === week),
    [items, week],
  );
  const localName = (names: Record<string, string>, fallback: string) =>
    names[locale] ?? names.en ?? fallback;

  const selected = districts.find((d) => d.district === district) ?? null;

  const describe = React.useCallback(
    (d: DistrictRollup) =>
      t("cropHealth.tooltip", {
        district: d.district,
        cases: formatNumber(d.cases),
        farmers: formatNumber(d.farmers),
      }),
    [t],
  );

  const districtColumns: ReadonlyArray<DataTableColumn<DistrictRollup>> = [
    {
      id: "district",
      header: t("cropHealth.column.district"),
      accessor: (d) => d.district,
      cell: (d) => (
        <span className="flex items-center gap-1 font-semibold">
          {d.district}
          {d.outbreaks > 0 ? (
            <Badge variant="danger" data-testid="outbreak-badge">
              {t("cropHealth.outbreak")}
            </Badge>
          ) : null}
        </span>
      ),
    },
    {
      id: "cases",
      header: t("cropHealth.column.cases"),
      numeric: true,
      accessor: (d) => d.cases,
      cell: (d) => formatNumber(d.cases),
    },
    {
      id: "farmers",
      header: t("cropHealth.column.farmers"),
      numeric: true,
      accessor: (d) => d.farmers,
      cell: (d) => formatNumber(d.farmers),
    },
  ];

  const cellColumns: ReadonlyArray<DataTableColumn<CropHealthCell>> = [
    {
      id: "crop",
      header: t("cropHealth.column.crop"),
      cell: (c) => localName(c.crop_names, c.crop_code),
    },
    {
      id: "problem",
      header: t("cropHealth.column.problem"),
      cell: (c) => (
        <span className="flex items-center gap-1">
          {localName(c.problem_names, c.problem_code)}
          {c.outbreak ? <Badge variant="danger">{t("cropHealth.outbreak")}</Badge> : null}
        </span>
      ),
    },
    {
      id: "cases",
      header: t("cropHealth.column.cases"),
      numeric: true,
      cell: (c) => formatNumber(c.confirmed_cases),
    },
    {
      id: "farmers",
      header: t("cropHealth.column.farmers"),
      numeric: true,
      cell: (c) => formatNumber(c.farmers_affected),
    },
    {
      id: "prior",
      header: t("cropHealth.column.prior"),
      numeric: true,
      cell: (c) => c.prior_mean.toFixed(1),
    },
  ];

  return (
    <>
      <PageHeader
        title={t("cropHealth.title")}
        subtitle={t("cropHealth.subtitle")}
        actions={
          <div className="flex flex-wrap items-end gap-3">
            <Choice
              id="crop-health-crop"
              label={t("cropHealth.filterCrop")}
              value={cropParam ?? ""}
              includeAll
              options={opts.crops.map((c) => ({ value: c.id, label: c.name }))}
              onChange={(v) => setCrop(v || undefined)}
            />
            <Choice
              id="crop-health-week"
              label={t("cropHealth.filterWeek")}
              value={week ?? ""}
              options={available.map((w) => ({ value: w, label: w }))}
              onChange={(v) => setWeek(v || undefined)}
            />
            <Choice
              id="crop-health-weeks"
              label={t("cropHealth.filterWeeks")}
              value={String(weeks)}
              options={WEEK_OPTIONS.map((n) => ({
                value: String(n),
                label: t("cropHealth.weeksOption", { n }),
              }))}
              onChange={(v) => setWeeks(v || undefined)}
            />
          </div>
        }
      />
      <Note icon={<MapPin className="size-4" aria-hidden="true" />} testId="crop-health-privacy">
        {t("cropHealth.privacy")}
      </Note>

      {health.isLoading && !health.data ? (
        <Skeleton announce className="h-80 w-full" />
      ) : health.error ? (
        <QueryError error={health.error} onRetry={() => void health.refetch()} />
      ) : districts.length === 0 ? (
        <DataTable
          columns={districtColumns}
          rows={[]}
          rowKey={(d) => d.district}
          emptyTitle={t("cropHealth.emptyTitle")}
          emptyHelp={t("cropHealth.emptyHelp")}
          caption={t("cropHealth.title")}
        />
      ) : (
        <>
          <div className="grid gap-4 lg:grid-cols-[3fr_2fr]">
            <div className="flex flex-col gap-2">
              <CropHealthMap
                districts={districts}
                describe={describe}
                selected={district ?? null}
                onSelect={(d) => setDistrict(d === district ? undefined : d)}
                attribution={t("map.attribution")}
                label={t("cropHealth.mapLabel")}
              />
              <p className="text-small text-text-muted">
                {t("cropHealth.legend")}
                {week
                  ? ` · ${t("cropHealth.weekLabel", {
                      week: week.split("W")[1] ?? week,
                      start: formatDateIst(
                        items.find((c) => weekKeyOf(c) === week)?.week_start ?? new Date(),
                      ),
                    })}`
                  : ""}
              </p>
            </div>
            <div className="flex flex-col gap-2">
              <h2 className="flex items-center gap-2 text-heading font-semibold">
                <AlertTriangle className="size-5 text-danger" aria-hidden="true" />
                {t("cropHealth.outbreaks")}
              </h2>
              <p className="text-small text-text-muted">{t("cropHealth.outbreakHelp")}</p>
              {outbreaks.length === 0 ? (
                <p className="text-body text-text-secondary" data-testid="no-outbreaks">
                  {t("cropHealth.noOutbreaks")}
                </p>
              ) : (
                <ul className="flex flex-col gap-1 text-small" data-testid="outbreak-list">
                  {outbreaks.map((c) => (
                    <li key={`${c.district}-${c.problem_code}-${c.iso_week}`}>
                      <button
                        type="button"
                        className="text-left text-primary underline"
                        onClick={() => setDistrict(c.district)}
                      >
                        {c.district} · {localName(c.crop_names, c.crop_code)} ·{" "}
                        {localName(c.problem_names, c.problem_code)} ({c.confirmed_cases})
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>

          <DataTable
            columns={districtColumns}
            rows={districts}
            rowKey={(d) => d.district}
            caption={t("cropHealth.title")}
            onRowClick={(d) => setDistrict(d.district === district ? undefined : d.district)}
            emptyTitle={t("cropHealth.emptyTitle")}
          />

          <section
            className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
            data-testid="crop-health-drill"
          >
            <h2 className="text-heading font-semibold">
              {selected && week
                ? t("cropHealth.drillTitle", {
                    district: selected.district,
                    week: week.split("W")[1] ?? week,
                  })
                : t("cropHealth.drillHelp")}
            </h2>
            {selected ? (
              <DataTable
                columns={cellColumns}
                rows={selected.cells}
                rowKey={(c) => `${c.crop_id}-${c.problem_id}-${c.iso_week}`}
                caption={selected.district}
                emptyTitle={t("cropHealth.emptyTitle")}
              />
            ) : null}
          </section>
        </>
      )}
    </>
  );
}
