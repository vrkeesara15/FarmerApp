"use client";

/**
 * AN-009 data quality, the second tab of the C70 inbox: flag volume by rule and type, how long
 * flags take to resolve (median and p90, not the mean — a handful left over a weekend drags an
 * average to nonsense), the VA-006 precision of each rule and the subjects flagged again and
 * again.
 *
 * Reads `GET /v1/flags/summary?days=` in the caller's inbox scope. It replaced the browser-side
 * roll-up of M7, which could only summarise the page of `/v1/flags` it had already fetched.
 */
import * as React from "react";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Skeleton } from "@/components/ds/Skeleton";
import { QueryError } from "@/components/admin/common";
import { Stat } from "@/components/growth/common";
import {
  DATA_QUALITY_WINDOWS,
  type RepeatSubject,
  type RuleVolume,
  type SubjectType,
} from "@/lib/flags";
import { formatDateTimeIst, formatNumber, formatPercent } from "@/lib/format";
import { useFlagSummary } from "@/lib/hooks/flags";
import { useT } from "@/lib/i18n-client";

export function DataQuality() {
  const t = useT();
  const [days, setDays] = React.useState<number>(90);
  const q = useFlagSummary(days);
  const s = q.data;
  const na = t("common.none");
  const hours = (v: number | null | undefined) =>
    v === null || v === undefined ? na : t("dataQuality.hours", { n: v.toFixed(1) });

  const ruleColumns: ReadonlyArray<DataTableColumn<RuleVolume>> = [
    {
      id: "rule",
      header: t("dataQuality.column.rule"),
      accessor: (r) => r.rule_id,
      sortable: true,
      cell: (r) => (
        <span className="flex flex-col">
          <span className="font-semibold">{r.rule_id}</span>
          {r.title ? <span className="text-small text-text-muted">{r.title}</span> : null}
        </span>
      ),
    },
    {
      id: "total",
      header: t("dataQuality.column.total"),
      numeric: true,
      accessor: (r) => r.total,
      sortable: true,
      cell: (r) => formatNumber(r.total),
    },
    {
      id: "open",
      header: t("dataQuality.column.open"),
      numeric: true,
      accessor: (r) => r.open,
      sortable: true,
      cell: (r) => formatNumber(r.open),
    },
    {
      id: "resolved",
      header: t("dataQuality.column.resolved"),
      numeric: true,
      accessor: (r) => r.resolved,
      sortable: true,
      cell: (r) => formatNumber(r.resolved),
    },
    {
      id: "medianHours",
      header: t("dataQuality.column.medianHours"),
      numeric: true,
      accessor: (r) => r.median_resolution_hours,
      sortable: true,
      cell: (r) => hours(r.median_resolution_hours),
    },
    {
      id: "p90Hours",
      header: t("dataQuality.column.p90Hours"),
      numeric: true,
      accessor: (r) => r.p90_resolution_hours,
      sortable: true,
      cell: (r) => hours(r.p90_resolution_hours),
    },
    {
      id: "falsePositives",
      header: t("dataQuality.column.falsePositives"),
      numeric: true,
      cell: (r) =>
        r.false_positive_rate === null
          ? na
          : `${formatNumber(r.false_positives)} (${formatPercent(r.false_positive_rate, 0)})`,
    },
    {
      id: "precision",
      header: t("dataQuality.column.precision"),
      numeric: true,
      accessor: (r) => r.precision,
      sortable: true,
      cell: (r) =>
        r.precision === null ? (
          na
        ) : (
          <span
            className={
              s && r.precision < s.precision_floor ? "font-semibold text-danger" : undefined
            }
            data-testid={`precision-${r.rule_id}`}
          >
            {formatPercent(r.precision, 0)}
          </span>
        ),
    },
  ];

  const repeatColumns: ReadonlyArray<DataTableColumn<RepeatSubject>> = [
    {
      id: "subject",
      header: t("dataQuality.repeatColumn.subject"),
      cell: (r) => (
        <span className="flex flex-col">
          <span>
            {t(`flags.subject.${r.subject_type as SubjectType}`)} · {r.subject_id.slice(0, 8)}
          </span>
          {r.title ? <span className="text-small text-text-muted">{r.title}</span> : null}
        </span>
      ),
    },
    {
      id: "count",
      header: t("dataQuality.repeatColumn.count"),
      numeric: true,
      accessor: (r) => r.flags,
      sortable: true,
      cell: (r) => formatNumber(r.flags),
    },
    {
      id: "open",
      header: t("dataQuality.column.open"),
      numeric: true,
      cell: (r) => formatNumber(r.open_flags),
    },
    {
      id: "rules",
      header: t("dataQuality.repeatColumn.rules"),
      cell: (r) => r.rules.join(", "),
    },
    {
      id: "last",
      header: t("dataQuality.repeatColumn.last"),
      cell: (r) => formatDateTimeIst(r.last_at),
    },
  ];

  if (q.isLoading && !s) return <Skeleton announce className="h-80 w-full" />;
  if (q.error) return <QueryError error={q.error} onRetry={() => void q.refetch()} />;
  if (!s) return null;

  return (
    <div className="flex flex-col gap-4 pt-3" data-testid="data-quality">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <p className="text-small text-text-muted" data-testid="data-quality-sample">
          {t("dataQuality.sample", { n: s.total })}
        </p>
        <div className="flex flex-col gap-1">
          <label htmlFor="dq-days" className="text-small font-semibold text-text-secondary">
            {t("dataQuality.window")}
          </label>
          <select
            id="dq-days"
            value={days}
            onChange={(e) => setDays(Number(e.target.value))}
            className="h-10 rounded-input border border-border bg-surface px-3 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary"
          >
            {DATA_QUALITY_WINDOWS.map((d) => (
              <option key={d} value={d}>
                {t("dataQuality.windowOption", { n: d })}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label={t("dataQuality.resolution")}
          value={hours(s.median_resolution_hours)}
          help={`${t("dataQuality.p90")}: ${hours(s.p90_resolution_hours)}`}
          testId="dq-resolution"
        />
        <Stat
          label={t("dataQuality.falsePositiveRate")}
          value={s.false_positive_rate === null ? na : formatPercent(s.false_positive_rate, 0)}
          help={t("dataQuality.falsePositiveHelp")}
          testId="dq-false-positive"
        />
        <Stat
          label={t("dataQuality.column.open")}
          value={formatNumber(s.open)}
          help={t("dataQuality.overdue", { n: s.overdue })}
        />
        <Stat label={t("dataQuality.column.resolved")} value={formatNumber(s.resolved)} />
      </div>

      <section className="flex flex-col gap-2">
        <h2 className="text-heading font-semibold">{t("dataQuality.bySubject")}</h2>
        <ul className="flex flex-wrap gap-4 text-small" data-testid="dq-subjects">
          {Object.entries(s.by_subject_type).map(([kind, n]) => (
            <li key={kind} className="tnum">
              {t(`flags.subject.${kind as SubjectType}`)}: <strong>{formatNumber(n)}</strong>
            </li>
          ))}
        </ul>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-heading font-semibold">{t("dataQuality.volume")}</h2>
        <p className="text-small text-text-muted">
          {t("dataQuality.precisionHelp", {
            floor: formatPercent(s.precision_floor, 0),
            weeks: s.precision_window_weeks,
          })}
        </p>
        <DataTable
          columns={ruleColumns}
          rows={s.by_rule}
          rowKey={(r) => r.rule_id}
          caption={t("dataQuality.volume")}
          emptyTitle={t("dataQuality.emptyTitle")}
          emptyHelp={t("dataQuality.emptyHelp")}
        />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-heading font-semibold">{t("dataQuality.repeat")}</h2>
        <p className="text-small text-text-muted">
          {t("dataQuality.repeatHelp", { n: s.repeat_min })}
        </p>
        <DataTable
          columns={repeatColumns}
          rows={s.repeat_subjects}
          rowKey={(r) => `${r.subject_type}-${r.subject_id}`}
          caption={t("dataQuality.repeat")}
          emptyTitle={t("dataQuality.repeatEmpty")}
        />
      </section>
    </div>
  );
}
