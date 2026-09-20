"use client";

/**
 * C62 diagnosis quality (AN-007). Reads `GET /v1/diagnoses/quality?days=` — the server summary
 * that replaced the browser-side computation of M6: corpus-answer share, escalation rate, the
 * review SLA, counts by source and status, top unknowns and the latest DX-011 evaluation run
 * (test-set accuracy per crop). The model-release gate lives on its own tab (DX-012).
 */
import * as React from "react";
import { AlertTriangle } from "lucide-react";
import { KpiCard } from "@/components/ds/KpiCard";
import { Skeleton } from "@/components/ds/Skeleton";
import { PageHeader, QueryError, RoleGate, SessionGate } from "@/components/admin/common";
import { Note } from "@/components/growth/common";
import { formatDateTimeIst, formatNumber, formatPercent } from "@/lib/format";
import { useDiagnosisQuality } from "@/lib/hooks/mlops";
import { QUALITY_ROLES, type DiagnosisQuality } from "@/lib/mlops";
import { useT } from "@/lib/i18n-client";
import { AgronomistSubNav, ReadOnlyNote, knownLabel, useCropNames } from "./common";

const DAY_OPTIONS = [7, 30, 90] as const;
const OOS = [
  "not_a_plant",
  "unsupported_crop",
  "unreadable_image",
  "no_match",
  "expert_not_diagnosable",
] as const;
const SOURCES = ["corpus", "llm", "agronomist", "none"] as const;
const STATUSES = ["confirmed", "provisional", "corrected", "out_of_scope", "queued"] as const;

export function QualityView() {
  const t = useT();
  const [days, setDays] = React.useState<number>(30);
  return (
    <div className="flex flex-col gap-4" data-screen="C62">
      <PageHeader title={t("quality.title")} subtitle={t("quality.subtitle", { days })} />
      <AgronomistSubNav />
      <SessionGate>
        <RoleGate roles={QUALITY_ROLES}>
          <ReadOnlyNote />
          <QualityContent days={days} onDaysChange={setDays} />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

const pct = (v: number | null | undefined, na: string) =>
  v === null || v === undefined ? na : formatPercent(v, 0);
const hrs = (v: number | null | undefined) => (v === null || v === undefined ? "—" : v.toFixed(1));

function QualityContent({
  days,
  onDaysChange,
}: {
  days: number;
  onDaysChange: (n: number) => void;
}) {
  const t = useT();
  const cropName = useCropNames();
  const q = useDiagnosisQuality(days);
  const na = t("quality.notAvailable");

  return (
    <div className="flex flex-col gap-4" data-testid="quality">
      <div className="flex flex-wrap items-end gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="quality-days" className="text-small font-semibold text-text-secondary">
            {t("quality.days")}
          </label>
          <select
            id="quality-days"
            value={days}
            onChange={(e) => onDaysChange(Number(e.target.value))}
            className="h-10 rounded-input border border-border bg-surface px-3 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary"
          >
            {DAY_OPTIONS.map((d) => (
              <option key={d} value={d}>
                {t("quality.daysOption", { n: d })}
              </option>
            ))}
          </select>
        </div>
      </div>

      {q.isLoading && !q.data ? (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          {Array.from({ length: 4 }, (_, i) => (
            <Skeleton key={i} announce={i === 0} className="h-28 w-full" />
          ))}
        </div>
      ) : q.error ? (
        <QueryError error={q.error} onRetry={() => void q.refetch()} />
      ) : q.data ? (
        <Summary data={q.data} cropName={cropName} na={na} />
      ) : null}
    </div>
  );
}

function Summary({
  data: s,
  cropName,
  na,
}: {
  data: DiagnosisQuality;
  cropName: (id: string | null) => string;
  na: string;
}) {
  const t = useT();
  const maxSource = Math.max(1, ...SOURCES.map((k) => s.by_source[k] ?? 0));
  const maxStatus = Math.max(1, ...STATUSES.map((k) => s.by_status[k] ?? 0));
  const ev = s.latest_evaluation;

  return (
    <>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          title={t("quality.requests")}
          value={formatNumber(s.requests)}
          footer={
            <span className="text-small text-text-muted">
              {t("quality.daysOption", { n: s.days })}
            </span>
          }
        />
        <KpiCard
          title={t("quality.answeredByCorpus")}
          value={pct(s.corpus_share, na)}
          footer={
            <span className="text-small text-text-muted">{t("quality.answeredByCorpusHelp")}</span>
          }
        />
        <KpiCard
          title={t("quality.escalation")}
          value={pct(s.escalation_rate, na)}
          footer={<span className="text-small text-text-muted">{t("quality.escalationHelp")}</span>}
        />
        <KpiCard
          title={t("quality.reviewSla")}
          value={pct(s.review.sla_rate, na)}
          footer={
            <span className="text-small text-text-muted">
              {t("quality.reviewWithin", {
                n: s.review.reviewed_within_sla,
                total: s.review.reviewed,
                hours: s.review.sla_hours,
              })}
            </span>
          }
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <section
          className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
          data-testid="quality-sources"
        >
          <h2 className="text-heading font-semibold">{t("quality.bySource")}</h2>
          <BarList
            rows={SOURCES.map((k) => ({
              key: k,
              label: t(`queue.source.${k}`),
              value: s.by_source[k] ?? 0,
            }))}
            max={maxSource}
          />
        </section>
        <section
          className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
          data-testid="quality-statuses"
        >
          <h2 className="text-heading font-semibold">{t("quality.byStatus")}</h2>
          <BarList
            rows={STATUSES.map((k) => ({
              key: k,
              label: t(`quality.statusLabel.${k}`),
              value: s.by_status[k] ?? 0,
            }))}
            max={maxStatus}
          />
        </section>
        <section
          className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
          data-testid="quality-review"
        >
          <h2 className="text-heading font-semibold">{t("quality.reviewTitle")}</h2>
          <p className="tnum text-body">
            {t("quality.reviewAvg", {
              avg: hrs(s.review.avg_review_hours),
              median: hrs(s.review.median_review_hours),
            })}
          </p>
          <p className="tnum text-body text-text-secondary">
            {t("quality.reviewOpen", {
              open: s.review.open_queue,
              overdue: s.review.open_overdue,
            })}
          </p>
        </section>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <section
          className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
          data-testid="quality-unknowns"
        >
          <h2 className="text-heading font-semibold">{t("quality.topUnknowns")}</h2>
          <p className="text-small text-text-muted">{t("quality.unknownsHelp")}</p>
          {s.top_unknowns.length === 0 ? (
            <p className="text-small text-text-secondary">{t("quality.unknownsEmpty")}</p>
          ) : (
            <ol className="flex flex-col gap-1 text-small">
              {s.top_unknowns.map((u) => (
                <li
                  key={`${u.crop_id ?? "none"}-${u.reason}`}
                  className="flex justify-between gap-2"
                  data-testid="unknown-row"
                >
                  <span>
                    {t("quality.unknownRow", {
                      crop: cropName(u.crop_id),
                      reason:
                        u.reason === "llm_unknown"
                          ? t("quality.unknownReason")
                          : knownLabel(t, u.reason, OOS, (r) => `review.oosReason.${r}` as const),
                    })}
                  </span>
                  <span className="tnum font-semibold">{u.cases}</span>
                </li>
              ))}
            </ol>
          )}
        </section>

        <section
          className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
          data-testid="quality-accuracy"
        >
          <h2 className="text-heading font-semibold">{t("quality.evaluation.title")}</h2>
          {!ev ? (
            <p className="text-small text-text-secondary" data-testid="evaluation-none">
              {t("quality.evaluation.none")}
            </p>
          ) : (
            <>
              <p className="text-small text-text-muted">
                {t("quality.evaluation.ranAt", { when: formatDateTimeIst(ev.ran_at) })} ·{" "}
                {t("quality.evaluation.model", {
                  name: ev.model_name ?? na,
                  version: ev.model_version ?? na,
                })}
              </p>
              <div className="grid grid-cols-3 gap-2">
                <Figure label={t("quality.evaluation.cases")} value={formatNumber(ev.cases)} />
                <Figure
                  label={t("quality.evaluation.top1")}
                  value={ev.top1_accuracy === null ? na : formatPercent(ev.top1_accuracy, 1)}
                  testId="eval-top1"
                />
                <Figure
                  label={t("quality.evaluation.delta")}
                  value={
                    ev.top1_delta_points === null
                      ? na
                      : t("quality.evaluation.deltaPoints", {
                          n: ev.top1_delta_points.toFixed(1),
                        })
                  }
                />
              </div>
              {ev.alerted ? (
                <Note
                  tone="warning"
                  icon={<AlertTriangle className="size-4" aria-hidden="true" />}
                  testId="eval-alert"
                >
                  {t("quality.evaluation.alerted")}
                </Note>
              ) : null}
              {ev.per_crop?.length ? (
                <table className="w-full text-small">
                  <caption className="sr-only">{t("quality.evaluation.perCrop")}</caption>
                  <thead>
                    <tr className="text-left text-text-muted">
                      <th scope="col">{t("quality.evaluation.column.crop")}</th>
                      <th scope="col" className="text-right">
                        {t("quality.evaluation.column.cases")}
                      </th>
                      <th scope="col" className="text-right">
                        {t("quality.evaluation.column.accuracy")}
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {ev.per_crop.map((row) => (
                      <tr key={row.crop_code} data-testid="eval-crop-row">
                        <td>{cropName(row.crop_id ?? null)}</td>
                        <td className="tnum text-right">{formatNumber(row.cases)}</td>
                        <td className="tnum text-right font-semibold">
                          {formatPercent(row.top1_accuracy, 1)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : null}
            </>
          )}
        </section>
      </div>
    </>
  );
}

function Figure({ label, value, testId }: { label: string; value: string; testId?: string }) {
  return (
    <div className="flex flex-col" data-testid={testId}>
      <span className="text-small text-text-muted">{label}</span>
      <span className="tnum text-heading font-semibold">{value}</span>
    </div>
  );
}

function BarList({
  rows,
  max,
}: {
  rows: Array<{ key: string; label: string; value: number; tone?: "danger" | "warning" }>;
  max: number;
}) {
  return (
    <ul className="flex flex-col gap-2">
      {rows.map((r) => (
        <li
          key={r.key}
          className="grid grid-cols-[7rem_1fr_2.5rem] items-center gap-2 text-small"
          data-testid={`bar-${r.key}`}
        >
          <span>{r.label}</span>
          <span className="h-3 overflow-hidden rounded-pill bg-background" aria-hidden="true">
            <span
              className={
                r.tone === "danger"
                  ? "block h-full bg-danger"
                  : r.tone === "warning"
                    ? "block h-full bg-warning"
                    : "block h-full bg-primary"
              }
              style={{ width: `${Math.round((r.value / max) * 100)}%` }}
            />
          </span>
          <span className="tnum text-right font-semibold">{r.value}</span>
        </li>
      ))}
    </ul>
  );
}
