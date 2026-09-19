"use client";

/**
 * C21 Officer profile (WC-002 / AN-002): summary cards from the scorecard, weekly trend,
 * visits per duty day, duty days (with a replay link per day), recent visits, and a date
 * picker into the C22 day replay. Store managers never get the replay entry (SPEC 2.6).
 */
import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { MapPinned } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { StatTile } from "@/components/ds/StatTile";
import { VisitScoreBadge } from "@/components/ds/VisitScoreBadge";
import { AnalyticsFilterBar } from "@/components/analytics/AnalyticsFilterBar";
import { BarCompare, CHART, CHART_SERIES, LineTrend } from "@/components/analytics/charts";
import { AnalyticsGate, PageHeader, Section, SectionSkeleton } from "@/components/analytics/Page";
import { ProblemState } from "@/components/analytics/ProblemState";
import { Badge } from "@/components/ui/badge";
import type { DutyDayOut, OfficerVisitOut } from "@/lib/analytics";
import {
  formatCount,
  formatDay,
  formatDayShort,
  formatDecimal,
  formatInrShort,
  formatRange,
  formatRatio,
  formatSeconds,
  formatTimeIst,
  purposeKey,
} from "@/lib/analytics-format";
import { csvFilename, downloadCsv, type CsvColumn } from "@/lib/csv";
import { formatDateTimeIst } from "@/lib/format";
import { useOfficer } from "@/lib/hooks/analytics";
import { useAnalyticsFilters } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";
import { canSeeReplay } from "@/lib/nav";
import { useSession } from "@/lib/session-context";

export function OfficerView({ id }: { id: string }) {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C21">
      <AnalyticsGate path="/field-team" title={t("fieldTeam.profileTitle")}>
        <Officer id={id} />
      </AnalyticsGate>
    </div>
  );
}

function replayHref(id: string, date: string, linkQuery: string): string {
  const qs = new URLSearchParams(linkQuery.replace(/^\?/, ""));
  qs.set("date", date);
  return `/field-team/${id}/replay?${qs.toString()}`;
}

function Officer({ id }: { id: string }) {
  const t = useT();
  const router = useRouter();
  const { role } = useSession();
  const filters = useAnalyticsFilters();
  const q = useOfficer(id, filters.apiFilters);
  const data = q.data;
  const replayAllowed = canSeeReplay(role) && (data?.location_visible ?? true);
  const [date, setDate] = React.useState<string>("");
  const replayDate = date || data?.duty_days[0]?.day || filters.filters.to;
  const back = { href: `/field-team${filters.linkQuery}`, label: t("fieldTeam.backToList") };

  if (q.error)
    return (
      <>
        <PageHeader title={t("fieldTeam.profileTitle")} back={back} />
        <ProblemState
          error={q.error}
          onRetry={() => void q.refetch()}
          onResetFilters={() => filters.reset()}
        />
      </>
    );

  const sc = data?.scorecard;
  const dutyColumns: DataTableColumn<DutyDayOut>[] = [
    {
      id: "day",
      header: t("fieldTeam.duty.day"),
      accessor: (d) => d.day,
      cell: (d) => formatDay(d.day),
      sortable: true,
    },
    { id: "start", header: t("fieldTeam.duty.start"), cell: (d) => formatTimeIst(d.start_at) },
    {
      id: "end",
      header: t("fieldTeam.duty.end"),
      cell: (d) => (d.end_at ? formatTimeIst(d.end_at) : t("fieldTeam.onDuty")),
    },
    ...(data?.location_visible
      ? [
          {
            id: "km",
            header: t("fieldTeam.duty.km"),
            accessor: (d: DutyDayOut) => d.km,
            cell: (d: DutyDayOut) => formatDecimal(d.km, 1),
            numeric: true,
            sortable: true,
          },
        ]
      : []),
    {
      id: "visits",
      header: t("fieldTeam.duty.visits"),
      accessor: (d) => d.visits,
      numeric: true,
      sortable: true,
    },
    {
      id: "verified",
      header: t("fieldTeam.duty.verified"),
      accessor: (d) => d.verified_visits,
      numeric: true,
      sortable: true,
    },
    {
      id: "tof",
      header: t("fieldTeam.duty.timeOnFarm"),
      accessor: (d) => d.time_on_farm_s,
      cell: (d) => formatSeconds(d.time_on_farm_s),
      numeric: true,
      sortable: true,
    },
    ...(replayAllowed
      ? [
          {
            id: "replay",
            header: t("fieldTeam.duty.replay"),
            cell: (d: DutyDayOut) => (
              <Link
                href={replayHref(id, d.day, filters.linkQuery)}
                className="text-primary hover:underline"
                aria-label={t("fieldTeam.replayOn", { date: formatDay(d.day) })}
              >
                {t("fieldTeam.duty.replay")}
              </Link>
            ),
          },
        ]
      : []),
  ];

  const visitColumns: DataTableColumn<OfficerVisitOut>[] = [
    {
      id: "when",
      header: t("fieldTeam.visits.when"),
      accessor: (v) => v.checkin_at,
      cell: (v) => formatDateTimeIst(v.checkin_at),
      sortable: true,
    },
    {
      id: "farmer",
      header: t("fieldTeam.visits.farmer"),
      accessor: (v) => v.farmer_name,
      cell: (v) => (
        <Link
          href={`/farmers/${v.farmer_id}${filters.linkQuery}`}
          className="text-text hover:text-primary"
        >
          {v.farmer_name}
        </Link>
      ),
      sortable: true,
    },
    {
      id: "purpose",
      header: t("fieldTeam.visits.purpose"),
      cell: (v) => t(`purpose.${purposeKey(v.purpose)}`),
    },
    {
      id: "score",
      header: t("fieldTeam.visits.score"),
      accessor: (v) => v.score,
      cell: (v) =>
        v.score === null ? (
          <Badge variant="neutral">{t("visitStatus.open")}</Badge>
        ) : (
          <VisitScoreBadge score={v.score} size="sm" />
        ),
      sortable: true,
    },
  ];

  const csvColumns: CsvColumn<DutyDayOut>[] = [
    { header: t("fieldTeam.duty.day"), value: (d) => formatDay(d.day) },
    { header: t("fieldTeam.duty.start"), value: (d) => formatTimeIst(d.start_at) },
    { header: t("fieldTeam.duty.end"), value: (d) => (d.end_at ? formatTimeIst(d.end_at) : "") },
    ...(data?.location_visible
      ? [{ header: t("fieldTeam.duty.km"), value: (d: DutyDayOut) => d.km }]
      : []),
    { header: t("fieldTeam.duty.visits"), value: (d) => d.visits },
    { header: t("fieldTeam.duty.verified"), value: (d) => d.verified_visits },
    {
      header: t("fieldTeam.columns.timeOnFarmMinutes"),
      value: (d) => Math.round(d.time_on_farm_s / 60),
    },
  ];

  const chrono = [...(data?.duty_days ?? [])].reverse();

  return (
    <>
      <PageHeader
        title={data?.name ?? t("fieldTeam.profileTitle")}
        back={back}
        subtitle={
          data ? (
            <span className="flex flex-wrap items-center gap-3">
              <span>{data.store_name ?? ""}</span>
              <Badge variant={data.on_duty ? "success" : "neutral"}>
                {data.on_duty ? t("fieldTeam.onDuty") : t("fieldTeam.offDuty")}
              </Badge>
              <span className="tnum">{formatRange(filters.filters.from, filters.filters.to)}</span>
            </span>
          ) : undefined
        }
        actions={
          replayAllowed ? (
            <div className="flex items-end gap-2" data-testid="replay-picker">
              <label className="flex flex-col gap-1 text-small font-semibold text-text-secondary">
                {t("fieldTeam.replayDate")}
                <input
                  type="date"
                  value={replayDate}
                  max={filters.filters.to}
                  onChange={(e) => setDate(e.target.value)}
                  className="tnum h-10 rounded-input border border-border bg-surface px-3 text-body text-text"
                />
              </label>
              <AppButton
                icon={<MapPinned />}
                onClick={() => router.push(replayHref(id, replayDate, filters.linkQuery))}
                disabled={!replayDate}
              >
                {t("fieldTeam.openReplay")}
              </AppButton>
            </div>
          ) : undefined
        }
      />
      <AnalyticsFilterBar
        state={filters}
        hide={{ officer: true }}
        onExport={
          data?.duty_days.length
            ? () =>
                downloadCsv(
                  csvFilename(`officer-${data.name}`, filters.filters.from, filters.filters.to),
                  csvColumns,
                  data.duty_days,
                )
            : undefined
        }
      />

      <section
        aria-label={t("fieldTeam.summary")}
        className="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-8"
        data-testid="officer-summary"
      >
        {sc ? (
          <>
            <StatTile label={t("fieldTeam.columns.rank")} value={`#${sc.rank}`} />
            <StatTile
              label={t("fieldTeam.columns.verifiedPerDay")}
              value={formatDecimal(sc.verified_visits_per_day, 1)}
            />
            <StatTile
              label={t("fieldTeam.columns.verifiedVisits")}
              value={formatCount(sc.verified_visits)}
            />
            <StatTile
              label={t("fieldTeam.columns.uniqueFarmers")}
              value={formatCount(sc.unique_farmers_reached)}
            />
            <StatTile
              label={t("fieldTeam.columns.confirmationRate")}
              value={formatRatio(sc.confirmation_rate)}
            />
            <StatTile
              label={t("fieldTeam.columns.timeOnFarm")}
              value={formatSeconds(sc.avg_time_on_farm_s)}
            />
            <StatTile
              label={t("fieldTeam.columns.conversion")}
              value={formatRatio(sc.conversion_rate)}
            />
            <StatTile
              label={t("fieldTeam.columns.collections")}
              value={formatInrShort(sc.collections_paise)}
            />
            {data?.location_visible ? (
              <StatTile
                label={t("fieldTeam.columns.kmPerDay")}
                value={formatDecimal(sc.km_per_day, 1)}
              />
            ) : null}
            <StatTile label={t("fieldTeam.columns.flags")} value={formatCount(sc.flags)} />
          </>
        ) : (
          Array.from({ length: 8 }, (_, i) => <StatTile key={i} label="" value="" loading />)
        )}
      </section>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Section title={t("fieldTeam.weeklyTrend")} testId="officer-trend">
          {sc ? (
            <LineTrend
              label={t("fieldTeam.weeklyTrend")}
              data={sc.trend.map((p) => ({ start: p.start, value: p.value }))}
              xKey="start"
              series={[
                {
                  key: "value",
                  label: t("fieldTeam.columns.verifiedVisits"),
                  color: CHART_SERIES[0],
                },
              ]}
              yFormat={(v) => formatCount(v)}
              xFormat={formatDayShort}
              titleFormat={(s) => {
                const p = sc.trend.find((x) => x.start === s);
                return p ? formatRange(p.start, p.end) : formatDay(s);
              }}
              height={220}
            />
          ) : (
            <SectionSkeleton />
          )}
        </Section>
        <Section title={t("fieldTeam.visitsPerDay")} testId="officer-days-chart">
          {data ? (
            <BarCompare
              label={t("fieldTeam.visitsPerDay")}
              data={chrono.map((d) => ({
                day: d.day,
                visits: d.visits,
                verified: d.verified_visits,
              }))}
              categoryKey="day"
              categoryFormat={formatDayShort}
              series={[
                { key: "visits", label: t("fieldTeam.duty.visits"), color: CHART.reference },
                { key: "verified", label: t("fieldTeam.duty.verified"), color: CHART_SERIES[0] },
              ]}
              valueFormat={(v) => formatCount(v)}
              height={220}
            />
          ) : (
            <SectionSkeleton />
          )}
        </Section>
      </div>

      <Section title={t("fieldTeam.dutyDays")} testId="duty-days">
        <DataTable
          caption={t("fieldTeam.dutyDays")}
          columns={dutyColumns}
          rows={data?.duty_days ?? []}
          rowKey={(d) => d.day}
          loading={q.isLoading}
          emptyTitle={t("fieldTeam.noDutyTitle")}
          emptyHelp={t("fieldTeam.noDutyHelp")}
        />
      </Section>
      <Section title={t("fieldTeam.recentVisits")} testId="recent-visits">
        <DataTable
          caption={t("fieldTeam.recentVisits")}
          columns={visitColumns}
          rows={data?.recent_visits ?? []}
          rowKey={(v) => v.id}
          loading={q.isLoading}
          emptyTitle={t("fieldTeam.noVisitsTitle")}
          emptyHelp={t("fieldTeam.noVisitsHelp")}
        />
      </Section>
    </>
  );
}
