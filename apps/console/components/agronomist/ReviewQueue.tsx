"use client";

/**
 * C60 Agronomist review queue (WC-006, DX-005, DX-006): provisional, out-of-scope and flagged
 * diagnoses oldest first with age and a live SLA countdown (warning at 18 h, breach at 24 h),
 * filters (crop, confidence, age, flagged); the detail panel shows the photos (zoom), the farm
 * context (crop, district, season, stage only), model candidates with scores, the LLM answer
 * ("Automated suggestion — verify") and the provenance; agronomists confirm or correct and the
 * farmer and officer are notified. Owners read only.
 */
import * as React from "react";
import { CheckCircle2, Flag, Send } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { ConfidenceBand } from "@/components/ds/ConfidenceBand";
import { EmptyState } from "@/components/ds/EmptyState";
import { Skeleton } from "@/components/ds/Skeleton";
import { Badge } from "@/components/ui/badge";
import {
  CheckboxField,
  PageHeader,
  QueryError,
  RoleGate,
  SelectField,
  SessionGate,
  useNow,
} from "@/components/admin/common";
import { CROP_STAGES, type CorpusProblem } from "@/lib/corpus";
import {
  AGE_FILTERS,
  CONFIDENCES,
  DIAGNOSIS_STATUSES,
  REVIEW_QUEUE_ROLES,
  REVIEW_ROLES,
  formatSpan,
  localName,
  type Confidence,
  type Diagnosis,
  type DiagnosisStatus,
  type ReviewQueueFilters,
  type ReviewQueueItem,
} from "@/lib/diagnosis";
import { formatDateTimeIst } from "@/lib/format";
import { useCrops } from "@/lib/hooks/catalog";
import { useReviewDiagnosis, useReviewQueue } from "@/lib/hooks/diagnosis";
import { useLocale, useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";
import {
  AgronomistSubNav,
  ReadOnlyNote,
  SlaBadge,
  knownLabel,
  useCropNames,
  useProblemIndex,
} from "./common";
import { CandidateTable, LlmAnswer, ProvenanceBlock, useNameOf } from "./Evidence";
import { PhotoGallery } from "./PhotoGallery";
import { ReviewForm } from "./ReviewForm";

const STATUS_VARIANT: Record<string, "warning" | "info" | "neutral" | "success"> = {
  provisional: "warning",
  out_of_scope: "neutral",
  answered: "info",
  confirmed: "success",
  corrected: "success",
  queued: "neutral",
};
const OOS = [
  "not_a_plant",
  "unsupported_crop",
  "unreadable_image",
  "no_match",
  "expert_not_diagnosable",
] as const;
const SEASON_KEYS = ["kharif", "rabi", "zaid"] as const;

export function ReviewQueue() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C60">
      <PageHeader title={t("queue.title")} subtitle={t("queue.subtitle")} />
      <AgronomistSubNav />
      <SessionGate>
        <RoleGate roles={REVIEW_QUEUE_ROLES}>
          <ReadOnlyNote />
          <QueueContent />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const t = useT();
  return (
    <Badge variant={STATUS_VARIANT[status] ?? "neutral"}>
      {knownLabel(
        t,
        status,
        DIAGNOSIS_STATUSES,
        (s: DiagnosisStatus) => `queue.status.${s}` as const,
      )}
    </Badge>
  );
}

function QueueContent() {
  const t = useT();
  const now = useNow(1000);
  const crops = useCrops();
  const cropName = useCropNames();
  const locale = useLocale();
  const { map: problems, problems: allProblems } = useProblemIndex();
  const [crop, setCrop] = React.useState("");
  const [confidence, setConfidence] = React.useState<Confidence | "">("");
  const [minAge, setMinAge] = React.useState("");
  const [flagged, setFlagged] = React.useState(false);
  const [selected, setSelected] = React.useState<string | null>(null);
  const [done, setDone] = React.useState<Diagnosis | null>(null);

  const filters: ReviewQueueFilters = {
    crop_id: crop || undefined,
    confidence: confidence ? [confidence] : undefined,
    min_age_hours: minAge ? Number(minAge) : undefined,
    flagged: flagged || undefined,
  };
  const queue = useReviewQueue(filters);
  const items = React.useMemo(
    () => (queue.data?.pages ?? []).flatMap((p) => p.items),
    [queue.data],
  );
  const counts = queue.data?.pages[0]?.counts;
  const current = items.find((i) => i.id === selected) ?? (done ? null : (items[0] ?? null));
  const filtered = !!(crop || confidence || minAge || flagged);

  const labelOf = (d: Pick<Diagnosis, "final_problem_id" | "result">) => {
    const id = d.final_problem_id ?? d.result?.problem?.id;
    if (!id) return t("queue.noLabel");
    const p = problems.get(id);
    if (p) return localName(p.names, locale, p.pest_code ?? id);
    return d.result?.problem
      ? localName(d.result.problem.names, locale, d.result.problem.code)
      : t("queue.noLabel");
  };

  const select = (id: string) => {
    setDone(null);
    setSelected(id);
  };

  return (
    <div className="flex flex-col gap-4">
      <section
        aria-label={t("queue.filters.label")}
        className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3"
        data-testid="queue-filters"
      >
        <SelectField
          label={t("queue.filters.crop")}
          value={crop}
          onChange={(e) => setCrop(e.target.value)}
          emptyLabel={t("common.all")}
          options={(crops.data ?? []).map((c) => ({
            value: c.id,
            label: localName(c.names, locale, c.name),
          }))}
          className="min-w-40"
        />
        <SelectField
          label={t("queue.filters.confidence")}
          value={confidence}
          onChange={(e) => setConfidence(e.target.value as Confidence | "")}
          emptyLabel={t("common.all")}
          options={CONFIDENCES.map((c) => ({ value: c, label: t(`confidence.${c}`) }))}
          className="min-w-40"
        />
        <SelectField
          label={t("queue.filters.age")}
          value={minAge}
          onChange={(e) => setMinAge(e.target.value)}
          emptyLabel={t("queue.filters.ageAny")}
          options={AGE_FILTERS.map((h) => ({
            value: String(h),
            label: t("queue.filters.ageOver", { n: h }),
          }))}
          className="min-w-40"
        />
        <CheckboxField
          label={t("queue.filters.flagged")}
          checked={flagged}
          onChange={(e) => setFlagged(e.target.checked)}
          className="pb-3"
        />
        {filtered ? (
          <AppButton
            variant="tertiary"
            onClick={() => {
              setCrop("");
              setConfidence("");
              setMinAge("");
              setFlagged(false);
            }}
          >
            {t("common.clear")}
          </AppButton>
        ) : null}
      </section>

      {counts ? (
        <div className="flex flex-wrap items-center gap-2" data-testid="queue-counts">
          <span className="tnum text-body font-semibold" data-testid="queue-total">
            {t("queue.total", { n: counts.total })}
          </span>
          <Badge variant={counts.overdue ? "danger" : "neutral"} data-testid="queue-overdue">
            {t("queue.overdue", { n: counts.overdue })}
          </Badge>
          {CONFIDENCES.map((c) =>
            counts.by_confidence[c] ? (
              <Badge key={c} variant="outline">
                {t(`confidence.${c}`)} · <span className="tnum">{counts.by_confidence[c]}</span>
              </Badge>
            ) : null,
          )}
          <span className="text-small text-text-muted">{t("queue.sortOldest")}</span>
        </div>
      ) : null}

      {queue.isLoading ? (
        <div className="grid gap-4 lg:grid-cols-[minmax(18rem,24rem)_1fr]">
          <div className="flex flex-col gap-2">
            {Array.from({ length: 4 }, (_, i) => (
              <Skeleton key={i} className="h-24 w-full" />
            ))}
          </div>
          <Skeleton className="h-96 w-full" />
        </div>
      ) : queue.error ? (
        <QueryError error={queue.error} onRetry={() => void queue.refetch()} />
      ) : items.length === 0 && !done ? (
        <EmptyState
          title={filtered ? t("queue.emptyFilteredTitle") : t("queue.emptyTitle")}
          help={filtered ? t("queue.emptyFiltered") : t("queue.empty")}
        />
      ) : (
        <div className="grid items-start gap-4 lg:grid-cols-[minmax(18rem,24rem)_1fr]">
          <div className="flex flex-col gap-2">
            <ul
              className="flex flex-col gap-2"
              aria-label={t("queue.title")}
              data-testid="queue-list"
            >
              {items.map((d) => (
                <li key={d.id}>
                  <button
                    type="button"
                    onClick={() => select(d.id)}
                    aria-current={current?.id === d.id ? "true" : undefined}
                    aria-label={`${t("queue.open")}: ${cropName(d.crop_id)}, ${labelOf(d)}`}
                    data-testid="queue-item"
                    data-id={d.id}
                    className={cn(
                      "flex w-full flex-col gap-1.5 rounded-card border bg-surface p-3 text-left hover:border-primary focus:outline-none focus:ring-2 focus:ring-primary",
                      current?.id === d.id ? "border-primary" : "border-border",
                    )}
                  >
                    <span className="flex flex-wrap items-center gap-1.5">
                      <span className="font-semibold">{cropName(d.crop_id)}</span>
                      <StatusBadge status={d.status} />
                      {d.confidence && (CONFIDENCES as readonly string[]).includes(d.confidence) ? (
                        <ConfidenceBand level={d.confidence as Confidence} />
                      ) : null}
                      {d.flagged ? (
                        <Badge variant="danger">
                          <Flag className="size-3" aria-hidden="true" />
                          {t("queue.flagged")}
                        </Badge>
                      ) : null}
                    </span>
                    <span className="text-small text-text-secondary">
                      {labelOf(d)} · {d.district ?? t("common.none")}
                    </span>
                    <span className="flex flex-wrap items-center justify-between gap-2 text-small">
                      <span className="tnum text-text-muted">
                        {t("queue.waiting", {
                          n: formatSpan(now - new Date(d.created_at).getTime()),
                        })}
                      </span>
                      <SlaBadge createdAt={d.created_at} overdue={d.overdue} now={now} />
                    </span>
                  </button>
                </li>
              ))}
            </ul>
            {queue.hasNextPage ? (
              <AppButton
                variant="secondary"
                onClick={() => void queue.fetchNextPage()}
                loading={queue.isFetchingNextPage}
              >
                {t("queue.loadMore")}
              </AppButton>
            ) : null}
          </div>
          <div>
            {done ? (
              <ReviewDone
                diagnosis={done}
                labelOf={labelOf}
                next={items[0] ?? null}
                onNext={(id) => select(id)}
              />
            ) : current ? (
              <ReviewDetail
                key={current.id}
                item={current}
                cropName={cropName(current.crop_id)}
                problems={problems}
                cropProblems={allProblems.filter(
                  (p) => p.crop_id === current.crop_id && p.status !== "retired",
                )}
                labelOf={labelOf}
                onReviewed={(d) => {
                  setSelected(null);
                  setDone(d);
                }}
              />
            ) : (
              <EmptyState title={t("queue.selectPrompt")} />
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function ReviewDetail({
  item,
  cropName,
  problems,
  cropProblems,
  labelOf,
  onReviewed,
}: {
  item: ReviewQueueItem;
  cropName: string;
  problems: Map<string, CorpusProblem>;
  cropProblems: CorpusProblem[];
  labelOf: (d: Pick<Diagnosis, "final_problem_id" | "result">) => string;
  onReviewed: (d: Diagnosis) => void;
}) {
  const t = useT();
  const { role } = useSession();
  const now = useNow(1000);
  const nameOf = useNameOf(problems, item.result?.problem);
  const review = useReviewDiagnosis(item.id);
  const currentId = item.final_problem_id ?? item.result?.problem?.id ?? null;
  const canReview = !!role && REVIEW_ROLES.includes(role);

  return (
    <article
      className="flex flex-col gap-4 rounded-card border border-border bg-surface p-4"
      aria-labelledby="review-heading"
      data-testid="review-detail"
    >
      <header className="flex flex-wrap items-start justify-between gap-2">
        <div className="flex flex-col gap-1">
          <h2 id="review-heading" className="text-heading font-semibold">
            {cropName} · {labelOf(item)}
          </h2>
          <span className="flex flex-wrap items-center gap-1.5">
            <StatusBadge status={item.status} />
            {item.confidence && (CONFIDENCES as readonly string[]).includes(item.confidence) ? (
              <ConfidenceBand level={item.confidence as Confidence} />
            ) : null}
            {item.flagged ? <Badge variant="danger">{t("queue.flagged")}</Badge> : null}
            {item.cta === "ask_expert" && item.status !== "out_of_scope" ? (
              <Badge variant="info">{t("queue.askExpert")}</Badge>
            ) : null}
          </span>
        </div>
        <SlaBadge createdAt={item.created_at} overdue={item.overdue} now={now} />
      </header>

      <PhotoGallery photos={item.images} />

      <section
        aria-labelledby="ctx-heading"
        className="flex flex-col gap-2"
        data-testid="farm-context"
      >
        <h3 id="ctx-heading" className="text-body font-semibold">
          {t("review.context")}
        </h3>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-small sm:grid-cols-4">
          <div>
            <dt className="text-text-muted">{t("review.crop")}</dt>
            <dd>{cropName}</dd>
          </div>
          <div>
            <dt className="text-text-muted">{t("review.district")}</dt>
            <dd>{item.district ?? t("common.none")}</dd>
          </div>
          <div>
            <dt className="text-text-muted">{t("review.season")}</dt>
            <dd>{knownLabel(t, item.season, SEASON_KEYS, (s) => `corpus.season.${s}` as const)}</dd>
          </div>
          <div>
            <dt className="text-text-muted">{t("review.stage")}</dt>
            <dd>{knownLabel(t, item.crop_stage, CROP_STAGES, (s) => `stage.${s}` as const)}</dd>
          </div>
          <div className="col-span-2">
            <dt className="text-text-muted">{t("review.captured")}</dt>
            <dd className="tnum">
              {item.captured_at ? formatDateTimeIst(item.captured_at) : t("common.none")}
            </dd>
          </div>
        </dl>
        <p className="text-small text-text-muted">{t("review.privacy")}</p>
      </section>

      <section className="flex flex-col gap-1" data-testid="current-label">
        <h3 className="text-body font-semibold">{t("review.currentLabel")}</h3>
        <p className="text-body">
          {item.status === "out_of_scope"
            ? t("review.outOfScope", {
                reason: knownLabel(
                  t,
                  item.out_of_scope_reason,
                  OOS,
                  (r) => `review.oosReason.${r}` as const,
                ),
              })
            : labelOf(item)}
        </p>
      </section>

      <CandidateTable diagnosis={item} nameOf={nameOf} />
      <LlmAnswer diagnosis={item} nameOf={nameOf} />
      <ProvenanceBlock diagnosis={item} />

      {item.reviews && item.reviews.length > 0 ? (
        <section className="flex flex-col gap-1">
          <h3 className="text-body font-semibold">{t("review.history")}</h3>
          <ul className="text-small">
            {item.reviews.map((r) => (
              <li key={r.id}>
                {formatDateTimeIst(r.created_at)} ·{" "}
                {t("review.historyEntry", {
                  action: r.action,
                  from: r.from_status,
                  to: r.to_status,
                })}
                {r.note ? ` — ${r.note}` : ""}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {canReview ? (
        <ReviewForm
          cropProblems={cropProblems}
          currentProblemId={currentId}
          cropName={cropName}
          canAddPhotos={item.images.length > 0}
          submitting={review.isPending}
          error={review.error ? problemMessage(review.error, t) : undefined}
          onSubmit={(body) => review.mutate(body, { onSuccess: onReviewed })}
        />
      ) : (
        <p className="text-small text-text-muted" data-testid="owner-note">
          {t("review.ownerNote")}
        </p>
      )}
    </article>
  );
}

function ReviewDone({
  diagnosis,
  labelOf,
  next,
  onNext,
}: {
  diagnosis: Diagnosis;
  labelOf: (d: Pick<Diagnosis, "final_problem_id" | "result">) => string;
  next: ReviewQueueItem | null;
  onNext: (id: string) => void;
}) {
  const t = useT();
  const last = diagnosis.reviews?.[diagnosis.reviews.length - 1];
  const added = last?.corpus_image_ids.length ?? 0;
  const status =
    diagnosis.status === "confirmed" || diagnosis.status === "corrected" ? diagnosis.status : null;
  return (
    <section
      className="bg-success-container/40 flex flex-col gap-3 rounded-card border border-success p-4"
      role="status"
      aria-labelledby="done-heading"
      data-testid="review-done"
    >
      <h2
        id="done-heading"
        className="flex items-center gap-2 text-heading font-semibold text-success"
      >
        <CheckCircle2 className="size-6" aria-hidden="true" />
        {t("review.done.title")}
      </h2>
      <p className="text-body" data-testid="review-result">
        {status
          ? t("review.done.result", {
              problem: labelOf(diagnosis),
              status: t(`queue.status.${status}`),
            })
          : t("review.done.notDiagnosable")}
      </p>
      <p className="flex items-center gap-2 text-body font-semibold" data-testid="review-notified">
        <Send className="size-4" aria-hidden="true" />
        {t("review.done.notified")}
      </p>
      {added > 0 ? (
        <p className="text-small text-text-secondary" data-testid="review-corpus-added">
          {t("review.done.corpusAdded", { n: added })}
        </p>
      ) : null}
      {next ? (
        <div>
          <AppButton variant="secondary" onClick={() => onNext(next.id)}>
            {t("review.done.next")}
          </AppButton>
        </div>
      ) : null}
    </section>
  );
}
