"use client";

/**
 * AN-009 data quality, the second tab of the C70 inbox: flag volume by rule, how long flags
 * take to resolve, the false-positive rate and the subjects flagged again and again.
 * Summarised in the browser from `/v1/flags` in the caller's inbox scope
 * (`summariseDataQuality()`, lib/data-quality.ts, unit-tested) — there is no summary endpoint.
 */
import * as React from "react";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Skeleton } from "@/components/ds/Skeleton";
import { QueryError, useNow } from "@/components/admin/common";
import { Stat } from "@/components/growth/common";
import { summariseDataQuality, type RepeatSubject, type RuleRow } from "@/lib/data-quality";
import { FLAG_STATUSES } from "@/lib/flags";
import { formatDateTimeIst, formatNumber, formatPercent } from "@/lib/format";
import { useFlagInbox } from "@/lib/hooks/flags";
import { useT } from "@/lib/i18n-client";

const REPEAT_MIN = 2;

export function DataQuality() {
  const t = useT();
  const now = useNow(60_000);
  // Every status: resolution time and the false-positive rate need the closed ones too.
  const inbox = useFlagInbox({ status: [...FLAG_STATUSES] });
  const flags = React.useMemo(
    () => (inbox.data?.pages ?? []).flatMap((p) => p.items),
    [inbox.data],
  );
  const s = React.useMemo(
    () => summariseDataQuality(flags, now, { repeatMin: REPEAT_MIN }),
    [flags, now],
  );
  const na = t("common.none");

  const ruleColumns: ReadonlyArray<DataTableColumn<RuleRow>> = [
    {
      id: "rule",
      header: t("dataQuality.column.rule"),
      accessor: (r) => r.rule,
      cell: (r) => <span className="font-semibold">{r.rule}</span>,
    },
    {
      id: "total",
      header: t("dataQuality.column.total"),
      numeric: true,
      accessor: (r) => r.total,
      cell: (r) => formatNumber(r.total),
    },
    {
      id: "open",
      header: t("dataQuality.column.open"),
      numeric: true,
      cell: (r) => formatNumber(r.open),
    },
    {
      id: "resolved",
      header: t("dataQuality.column.resolved"),
      numeric: true,
      cell: (r) => formatNumber(r.resolved),
    },
    {
      id: "avgHours",
      header: t("dataQuality.column.avgHours"),
      numeric: true,
      cell: (r) =>
        r.avgResolutionHours === null
          ? na
          : t("dataQuality.hours", { n: r.avgResolutionHours.toFixed(1) }),
    },
    {
      id: "falsePositives",
      header: t("dataQuality.column.falsePositives"),
      numeric: true,
      cell: (r) =>
        r.falsePositiveRate === null
          ? na
          : `${formatNumber(r.falsePositives)} (${formatPercent(r.falsePositiveRate, 0)})`,
    },
  ];

  const repeatColumns: ReadonlyArray<DataTableColumn<RepeatSubject>> = [
    {
      id: "subject",
      header: t("dataQuality.repeatColumn.subject"),
      cell: (r) =>
        `${t(`flags.subject.${r.subject_type}` as "flags.subject.farmer")} · ${r.subject_id.slice(0, 8)}`,
    },
    {
      id: "count",
      header: t("dataQuality.repeatColumn.count"),
      numeric: true,
      accessor: (r) => r.count,
      cell: (r) => formatNumber(r.count),
    },
    {
      id: "rules",
      header: t("dataQuality.repeatColumn.rules"),
      cell: (r) => r.rules.join(", "),
    },
    {
      id: "last",
      header: t("dataQuality.repeatColumn.last"),
      cell: (r) => formatDateTimeIst(r.lastAt),
    },
  ];

  if (inbox.isLoading && !inbox.data) return <Skeleton announce className="h-80 w-full" />;
  if (inbox.error) return <QueryError error={inbox.error} onRetry={() => void inbox.refetch()} />;

  return (
    <div className="flex flex-col gap-4 pt-3" data-testid="data-quality">
      <p className="text-small text-text-muted" data-testid="data-quality-sample">
        {t("dataQuality.sample", { n: s.total })}
      </p>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label={t("dataQuality.resolution")}
          value={
            s.avgResolutionHours === null
              ? na
              : t("dataQuality.hours", { n: s.avgResolutionHours.toFixed(1) })
          }
          help={
            s.medianResolutionHours === null
              ? undefined
              : `${t("dataQuality.median")}: ${t("dataQuality.hours", {
                  n: s.medianResolutionHours.toFixed(1),
                })}`
          }
          testId="dq-resolution"
        />
        <Stat
          label={t("dataQuality.falsePositiveRate")}
          value={s.falsePositiveRate === null ? na : formatPercent(s.falsePositiveRate, 0)}
          help={t("dataQuality.falsePositiveHelp")}
          testId="dq-false-positive"
        />
        <Stat label={t("dataQuality.column.open")} value={formatNumber(s.open)} />
        <Stat label={t("dataQuality.column.resolved")} value={formatNumber(s.resolved)} />
      </div>

      <section className="flex flex-col gap-2">
        <h2 className="text-heading font-semibold">{t("dataQuality.volume")}</h2>
        <DataTable
          columns={ruleColumns}
          rows={s.byRule}
          rowKey={(r) => r.rule}
          caption={t("dataQuality.volume")}
          emptyTitle={t("dataQuality.emptyTitle")}
          emptyHelp={t("dataQuality.emptyHelp")}
        />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-heading font-semibold">{t("dataQuality.repeat")}</h2>
        <p className="text-small text-text-muted">
          {t("dataQuality.repeatHelp", { n: REPEAT_MIN })}
        </p>
        <DataTable
          columns={repeatColumns}
          rows={s.repeatSubjects}
          rowKey={(r) => `${r.subject_type}-${r.subject_id}`}
          caption={t("dataQuality.repeat")}
          emptyTitle={t("dataQuality.repeatEmpty")}
        />
      </section>
    </div>
  );
}
