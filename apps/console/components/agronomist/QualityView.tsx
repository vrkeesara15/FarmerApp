"use client";

/**
 * C62 Diagnosis quality — basic view (AN-007 subset): answered-by-corpus share, counts by source,
 * escalation rate, review SLA, queue age distribution and top unknowns, computed in the browser
 * from the review queue and the last 30 days of diagnoses. Test-set accuracy and the full
 * dashboard arrive with AN-007 (M7), which replaces this screen's data source.
 */
import * as React from "react";
import { Info } from "lucide-react";
import { KpiCard } from "@/components/ds/KpiCard";
import { Skeleton } from "@/components/ds/Skeleton";
import { PageHeader, QueryError, RoleGate, SessionGate, useNow } from "@/components/admin/common";
import { REVIEW_QUEUE_ROLES } from "@/lib/diagnosis";
import { AGE_BUCKETS, summariseQuality } from "@/lib/diagnosis-quality";
import { formatPercent } from "@/lib/format";
import { useRecentDiagnoses, useReviewQueue } from "@/lib/hooks/diagnosis";
import { useT } from "@/lib/i18n-client";
import { AgronomistSubNav, ReadOnlyNote, knownLabel, useCropNames } from "./common";

const DAYS = 30;
const OOS = [
  "not_a_plant",
  "unsupported_crop",
  "unreadable_image",
  "no_match",
  "expert_not_diagnosable",
] as const;
const SOURCES = ["corpus", "llm", "agronomist", "none"] as const;

export function QualityView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C62">
      <PageHeader title={t("quality.title")} subtitle={t("quality.subtitle", { days: DAYS })} />
      <AgronomistSubNav />
      <SessionGate>
        <RoleGate roles={REVIEW_QUEUE_ROLES}>
          <ReadOnlyNote />
          <QualityContent />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

const pct = (v: number | null, na: string) => (v === null ? na : formatPercent(v, 0));

function QualityContent() {
  const t = useT();
  const now = useNow(60_000);
  const cropName = useCropNames();
  const recent = useRecentDiagnoses(DAYS);
  const queue = useReviewQueue({ limit: 200 });
  const queueItems = React.useMemo(
    () => (queue.data?.pages ?? []).flatMap((p) => p.items),
    [queue.data],
  );
  const counts = queue.data?.pages[0]?.counts;
  const s = React.useMemo(
    () => summariseQuality(recent.data ?? [], queueItems, now),
    [recent.data, queueItems, now],
  );
  const na = t("quality.notAvailable");

  if (recent.isLoading || queue.isLoading)
    return (
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }, (_, i) => (
          <Skeleton key={i} className="h-28 w-full" />
        ))}
      </div>
    );
  if (recent.error || queue.error)
    return (
      <QueryError
        error={recent.error ?? queue.error}
        onRetry={() => {
          void recent.refetch();
          void queue.refetch();
        }}
      />
    );

  const maxSource = Math.max(1, ...SOURCES.map((k) => s.bySource[k]));
  const maxAge = Math.max(1, ...AGE_BUCKETS.map((b) => s.queueAges[b]));

  return (
    <div className="flex flex-col gap-4" data-testid="quality">
      <p
        className="flex items-start gap-2 rounded-card border border-border bg-info-container px-3 py-2 text-small text-info"
        role="note"
        data-testid="quality-interim"
      >
        <Info className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {t("quality.interim")}
      </p>
      <p className="tnum text-small text-text-secondary">
        {t("quality.sample", { n: s.total, days: DAYS })}
      </p>

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          title={t("quality.answeredByCorpus")}
          value={pct(s.corpusShare, na)}
          footer={
            <span className="text-small text-text-muted">{t("quality.answeredByCorpusHelp")}</span>
          }
        />
        <KpiCard
          title={t("quality.escalation")}
          value={pct(s.escalationRate, na)}
          footer={<span className="text-small text-text-muted">{t("quality.escalationHelp")}</span>}
        />
        <KpiCard
          title={t("quality.reviewSla")}
          value={pct(s.reviewedIn24h, na)}
          footer={<span className="text-small text-text-muted">{t("quality.reviewSlaHelp")}</span>}
        />
        <KpiCard
          title={t("quality.queue")}
          value={t("quality.count", { n: counts?.total ?? 0 })}
          footer={
            <span className="text-small text-text-muted">
              {t("quality.queueHelp", { overdue: counts?.overdue ?? 0 })}
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
              value: s.bySource[k],
            }))}
            max={maxSource}
          />
        </section>
        <section
          className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
          data-testid="quality-queue-age"
        >
          <h2 className="text-heading font-semibold">{t("quality.queueAge")}</h2>
          <BarList
            rows={AGE_BUCKETS.map((b) => ({
              key: b,
              label: t(`quality.buckets.${b}`),
              value: s.queueAges[b],
              tone: b === "gt24" ? "danger" : b === "h18to24" ? "warning" : undefined,
            }))}
            max={maxAge}
          />
        </section>
        <section
          className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
          data-testid="quality-unknowns"
        >
          <h2 className="text-heading font-semibold">{t("quality.topUnknowns")}</h2>
          <p className="text-small text-text-muted">{t("quality.unknownsHelp")}</p>
          {s.topUnknowns.length === 0 ? (
            <p className="text-small text-text-secondary">{t("quality.unknownsEmpty")}</p>
          ) : (
            <ol className="flex flex-col gap-1 text-small">
              {s.topUnknowns.map((u) => (
                <li
                  key={`${u.cropId}-${u.reason}`}
                  className="flex justify-between gap-2"
                  data-testid="unknown-row"
                >
                  <span>
                    {t("quality.unknownRow", {
                      crop: cropName(u.cropId),
                      reason:
                        u.reason === "llm_unknown"
                          ? t("quality.unknownReason")
                          : knownLabel(t, u.reason, OOS, (r) => `review.oosReason.${r}` as const),
                    })}
                  </span>
                  <span className="tnum font-semibold">{u.count}</span>
                </li>
              ))}
            </ol>
          )}
        </section>
      </div>

      <section
        className="flex flex-col gap-1 rounded-card border border-dashed border-border bg-surface p-4"
        data-testid="quality-accuracy"
      >
        <h2 className="text-heading font-semibold">{t("quality.accuracy")}</h2>
        <p className="text-small text-text-secondary">{t("quality.accuracyPending")}</p>
      </section>
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
