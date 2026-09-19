"use client";

/**
 * C61 Corpus manager (WC-007, SPEC 3.2): problems per crop with status chips, create / edit
 * (names and symptoms per language), the images grid per problem with chunked upload and
 * embedding status, per-image metadata, the draft -> reviewed -> approved -> retired workflow
 * (agronomist only; approval is the regulatory human gate and bumps the corpus version) and the
 * version history. "Only approved entries are used in production"; a filter shows exactly that.
 */
import * as React from "react";
import { Cpu, Info, Pencil, Plus, ShieldCheck, Upload } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { AppTextField } from "@/components/ds/AppTextField";
import { Dialog } from "@/components/ds/Dialog";
import { EmptyState } from "@/components/ds/EmptyState";
import { Skeleton } from "@/components/ds/Skeleton";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import {
  CheckboxField,
  PageHeader,
  QueryError,
  RoleGate,
  SelectField,
  SessionGate,
} from "@/components/admin/common";
import { ApiError } from "@/lib/api";
import {
  CORPUS_READ_ROLES,
  CORPUS_SOURCES,
  CORPUS_STATUSES,
  CORPUS_WRITE_ROLES,
  CROP_STAGES,
  IMAGE_PARTS,
  IMAGE_SEVERITIES,
  PRODUCTION_STATUSES,
  PROBLEM_TYPES,
  SEASONS,
  bumpsVersion,
  corpusActions,
  isEditable,
  servedImageCount,
  type CorpusImage,
  type CorpusProblem,
  type CorpusSource,
  type CorpusStatus,
  type ImagePart,
  type ImageSeverity,
} from "@/lib/corpus";
import { localName } from "@/lib/diagnosis";
import { formatDateTimeIst } from "@/lib/format";
import { useCrops } from "@/lib/hooks/catalog";
import {
  useApproveCorpus,
  useCorpusImages,
  useCorpusProblems,
  useCorpusVersions,
  useTransitionImage,
  useTransitionProblem,
  useUploadCorpusImage,
} from "@/lib/hooks/diagnosis";
import { LOCALES, type Locale } from "@/lib/i18n";
import { useLocale, useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";
import {
  AgronomistSubNav,
  CorpusStatusChip,
  ReadOnlyNote,
  knownLabel,
  useCropNames,
} from "./common";
import { ProblemDialog } from "./ProblemDialog";

const ACTION_KEYS = {
  reviewed: "corpus.actions.reviewed",
  approved: "corpus.actions.approved",
  draft: "corpus.actions.draft",
  retired: "corpus.actions.retired",
} as const;

/** `invalid_transition` is shared with flags; say it in corpus words here. */
function corpusError(err: unknown, t: ReturnType<typeof useT>): string {
  if (err instanceof ApiError && err.problem.code === "invalid_transition")
    return t("problems.corpusTransition");
  return problemMessage(err, t);
}

export function CorpusManager() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C61">
      <PageHeader title={t("corpus.title")} subtitle={t("corpus.subtitle")} />
      <AgronomistSubNav />
      <SessionGate>
        <RoleGate roles={CORPUS_READ_ROLES}>
          <ReadOnlyNote />
          <CorpusContent />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function CorpusContent() {
  const t = useT();
  const locale = useLocale();
  const { role } = useSession();
  const canWrite = !!role && CORPUS_WRITE_ROLES.includes(role);
  const crops = useCrops();
  const cropName = useCropNames();
  const [crop, setCrop] = React.useState("");
  const [status, setStatus] = React.useState<CorpusStatus | "">("");
  const [source, setSource] = React.useState<CorpusSource | "">("");
  const [production, setProduction] = React.useState(false);
  const [selected, setSelected] = React.useState<string | null>(null);
  const [creating, setCreating] = React.useState(false);
  const [editing, setEditing] = React.useState<CorpusProblem | null>(null);

  const filters = {
    crop_id: crop || undefined,
    status: production ? [...PRODUCTION_STATUSES] : status ? [status] : undefined,
    source: source || undefined,
  };
  const list = useCorpusProblems(filters);
  const all = useCorpusProblems({});
  const items = list.data?.items ?? [];
  const version = all.data?.corpus_version ?? list.data?.corpus_version;
  const current = (all.data?.items ?? []).find((p) => p.id === selected) ?? null;

  return (
    <div className="flex flex-col gap-4">
      <div
        className="flex flex-wrap items-center justify-between gap-3 rounded-card border border-primary bg-primary-container px-4 py-3"
        role="note"
        data-testid="production-note"
      >
        <p className="flex items-center gap-2 text-body text-text">
          <ShieldCheck className="size-5 shrink-0 text-primary" aria-hidden="true" />
          {t("corpus.productionNote")}
        </p>
        {version !== undefined ? (
          <Badge variant="default" data-testid="corpus-version" className="tnum">
            {t("corpus.version", { v: version })}
          </Badge>
        ) : null}
      </div>

      <section
        aria-label={t("corpus.filters.label")}
        className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3"
        data-testid="corpus-filters"
      >
        <SelectField
          label={t("corpus.filters.crop")}
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
          label={t("corpus.filters.status")}
          value={production ? "approved" : status}
          disabled={production}
          onChange={(e) => setStatus(e.target.value as CorpusStatus | "")}
          emptyLabel={t("common.all")}
          options={CORPUS_STATUSES.map((s) => ({ value: s, label: t(`corpus.status.${s}`) }))}
          className="min-w-40"
        />
        <SelectField
          label={t("corpus.filters.source")}
          value={source}
          onChange={(e) => setSource(e.target.value as CorpusSource | "")}
          emptyLabel={t("common.all")}
          options={CORPUS_SOURCES.map((s) => ({ value: s, label: t(`corpus.source.${s}`) }))}
          className="min-w-40"
        />
        <CheckboxField
          label={t("corpus.filters.production")}
          checked={production}
          onChange={(e) => setProduction(e.target.checked)}
          className="pb-3"
        />
        {canWrite ? (
          <AppButton
            icon={<Plus aria-hidden="true" />}
            onClick={() => setCreating(true)}
            className="ml-auto"
          >
            {t("corpus.new")}
          </AppButton>
        ) : null}
      </section>

      {list.isLoading ? (
        <Skeleton className="h-64 w-full" />
      ) : list.error ? (
        <QueryError error={list.error} onRetry={() => void list.refetch()} />
      ) : items.length === 0 ? (
        <EmptyState title={t("corpus.emptyTitle")} help={t("corpus.empty")} />
      ) : (
        <div className="overflow-x-auto rounded-card border border-border bg-surface">
          <table className="w-full text-body" data-testid="corpus-table">
            <thead>
              <tr className="border-b border-border text-left text-small text-text-muted">
                <th scope="col" className="px-3 py-2 font-semibold">
                  {t("corpus.columns.problem")}
                </th>
                <th scope="col" className="px-3 py-2 font-semibold">
                  {t("corpus.columns.crop")}
                </th>
                <th scope="col" className="px-3 py-2 font-semibold">
                  {t("corpus.columns.type")}
                </th>
                <th scope="col" className="px-3 py-2 font-semibold">
                  {t("corpus.columns.status")}
                </th>
                <th scope="col" className="px-3 py-2 font-semibold">
                  {t("corpus.columns.images")}
                </th>
                <th scope="col" className="px-3 py-2 text-right font-semibold">
                  {t("corpus.columns.served")}
                </th>
                <th scope="col" className="px-3 py-2 font-semibold">
                  {t("corpus.columns.source")}
                </th>
                <th scope="col" className="px-3 py-2 text-right font-semibold">
                  {t("corpus.columns.approvedIn")}
                </th>
              </tr>
            </thead>
            <tbody>
              {items.map((p) => {
                const name = localName(p.names, locale, p.pest_code ?? p.id);
                return (
                  <tr
                    key={p.id}
                    data-testid="corpus-row"
                    data-status={p.status}
                    className={cn(
                      "border-b border-border last:border-0",
                      selected === p.id && "bg-primary-container/50",
                    )}
                  >
                    <td className="px-3 py-2">
                      <button
                        type="button"
                        className="text-left font-semibold text-primary hover:underline"
                        onClick={() => setSelected(p.id)}
                        aria-label={t("corpus.open", { name })}
                      >
                        {name}
                      </button>
                      {locale !== "en" && p.names.en !== name ? (
                        <span className="block text-small text-text-muted">{p.names.en}</span>
                      ) : null}
                    </td>
                    <td className="px-3 py-2">{cropName(p.crop_id)}</td>
                    <td className="px-3 py-2">
                      {knownLabel(
                        t,
                        p.problem_type,
                        PROBLEM_TYPES,
                        (x) => `corpus.type.${x}` as const,
                      )}
                    </td>
                    <td className="px-3 py-2">
                      <CorpusStatusChip status={p.status} />
                    </td>
                    <td className="tnum px-3 py-2 text-small text-text-secondary">
                      {t("corpus.imageCounts", {
                        approved: p.image_counts.approved ?? 0,
                        reviewed: p.image_counts.reviewed ?? 0,
                        draft: p.image_counts.draft ?? 0,
                      })}
                    </td>
                    <td className="tnum px-3 py-2 text-right" data-testid="served-count">
                      {servedImageCount(p)}
                    </td>
                    <td className="px-3 py-2 text-small">
                      {knownLabel(
                        t,
                        p.source,
                        CORPUS_SOURCES,
                        (s) => `corpus.source.${s}` as const,
                      )}
                    </td>
                    <td className="tnum px-3 py-2 text-right">
                      {p.approved_in_version ? `v${p.approved_in_version}` : t("common.none")}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {current ? (
        <ProblemDetail
          key={current.id}
          problem={current}
          cropName={cropName(current.crop_id)}
          version={version ?? 0}
          production={production}
          canWrite={canWrite}
          onEdit={() => setEditing(current)}
          onClose={() => setSelected(null)}
        />
      ) : null}

      <VersionHistory />

      {creating ? (
        <ProblemDialog
          open
          onOpenChange={setCreating}
          problem={null}
          existing={all.data?.items ?? []}
          defaultCropId={crop || undefined}
          onSaved={(p) => {
            setCreating(false);
            setSelected(p.id);
            toast.success(t("corpus.moved", { status: t("corpus.status.draft") }));
          }}
        />
      ) : null}
      {editing ? (
        <ProblemDialog
          open
          onOpenChange={(o) => !o && setEditing(null)}
          problem={editing}
          existing={all.data?.items ?? []}
          onSaved={() => setEditing(null)}
        />
      ) : null}
    </div>
  );
}

// ---- workflow ----------------------------------------------------------------------------
function WorkflowButtons({
  status,
  onAction,
  testId,
  size = "M",
}: {
  status: CorpusStatus;
  onAction: (to: CorpusStatus) => void;
  testId: string;
  size?: "M" | "L";
}) {
  const t = useT();
  const { role } = useSession();
  const actions = corpusActions(status, role);
  if (!actions.length) return null;
  return (
    <div
      className="flex flex-wrap gap-2"
      role="group"
      aria-label={t("corpus.actions.label")}
      data-testid={testId}
    >
      {actions.map((to) => (
        <AppButton
          key={to}
          size={size}
          variant={to === "approved" ? "primary" : to === "retired" ? "destructive" : "secondary"}
          onClick={() => onAction(to)}
        >
          {t(ACTION_KEYS[to])}
        </AppButton>
      ))}
    </div>
  );
}

interface PendingMove {
  kind: "problem" | "image";
  id: string;
  from: CorpusStatus;
  to: "approved" | "retired";
  /** Reviewed images approved together with a problem. */
  imageIds: string[];
}

function MoveDialog({
  move,
  version,
  onClose,
}: {
  move: PendingMove;
  version: number;
  onClose: () => void;
}) {
  const t = useT();
  const [checked, setChecked] = React.useState(false);
  const [withImages, setWithImages] = React.useState(move.imageIds.length > 0);
  const [note, setNote] = React.useState("");
  const [gateError, setGateError] = React.useState(false);
  const approveSet = useApproveCorpus();
  const moveProblem = useTransitionProblem();
  const moveImage = useTransitionImage();
  const pending = approveSet.isPending || moveProblem.isPending || moveImage.isPending;
  const error = approveSet.error ?? moveProblem.error ?? moveImage.error;
  const approving = move.to === "approved";
  const bumps = bumpsVersion(move.from, move.to);

  const done = (bumped: boolean) => {
    toast.success(
      bumped
        ? t("corpus.bumped", { v: version + 1 })
        : t("corpus.moved", { status: t(`corpus.status.${move.to}`) }),
    );
    onClose();
  };

  const confirm = () => {
    if (approving && !checked) {
      setGateError(true);
      return;
    }
    const n = note.trim() || null;
    if (move.kind === "problem" && approving && withImages && move.imageIds.length) {
      approveSet.mutate(
        { problem_ids: [move.id], image_ids: move.imageIds, note: n },
        { onSuccess: () => done(true) },
      );
    } else if (move.kind === "problem") {
      moveProblem.mutate({ id: move.id, to: move.to, note: n }, { onSuccess: () => done(bumps) });
    } else {
      moveImage.mutate({ id: move.id, to: move.to, note: n }, { onSuccess: () => done(bumps) });
    }
  };

  return (
    <Dialog
      open
      onOpenChange={(o) => !o && onClose()}
      title={approving ? t("corpus.approve.title") : t("corpus.retire.title")}
      confirmLabel={approving ? t("corpus.approve.confirm") : t("corpus.retire.confirm")}
      destructive={!approving}
      onConfirm={confirm}
      loading={pending}
      error={error ? corpusError(error, t) : gateError ? t("corpus.approve.gate") : undefined}
    >
      <div className="flex flex-col gap-3" data-testid="move-dialog">
        {approving ? (
          <>
            <p className="text-body" data-testid="approve-bump">
              {t("corpus.approve.body", { from: version, to: version + 1 })}
            </p>
            <p className="flex gap-2 rounded-card border border-warning bg-warning-container px-3 py-2 text-small text-text">
              <ShieldCheck className="size-5 shrink-0 text-warning" aria-hidden="true" />
              {t("corpus.approve.gate")}
            </p>
            {move.imageIds.length ? (
              <CheckboxField
                label={t("corpus.approve.includeImages", { n: move.imageIds.length })}
                checked={withImages}
                onChange={(e) => setWithImages(e.target.checked)}
              />
            ) : null}
            <CheckboxField
              label={t("corpus.approve.check")}
              checked={checked}
              onChange={(e) => {
                setChecked(e.target.checked);
                setGateError(false);
              }}
            />
          </>
        ) : (
          <p className="text-body">{t("corpus.retire.body")}</p>
        )}
        <AppTextField
          label={t("corpus.transitionNote")}
          value={note}
          maxLength={2000}
          onChange={(e) => setNote(e.target.value)}
          optional
        />
      </div>
    </Dialog>
  );
}

// ---- problem detail ----------------------------------------------------------------------
function ProblemDetail({
  problem,
  cropName,
  version,
  production,
  canWrite,
  onEdit,
  onClose,
}: {
  problem: CorpusProblem;
  cropName: string;
  version: number;
  production: boolean;
  canWrite: boolean;
  onEdit: () => void;
  onClose: () => void;
}) {
  const t = useT();
  const locale = useLocale();
  const [lang, setLang] = React.useState<Locale>(locale);
  const [move, setMove] = React.useState<PendingMove | null>(null);
  const images = useCorpusImages(problem.id);
  const moveProblem = useTransitionProblem();
  const moveImage = useTransitionImage();
  const name = localName(problem.names, locale, problem.pest_code ?? problem.id);
  const all = images.data?.items ?? [];
  const shown = production
    ? problem.status === "approved"
      ? all.filter((i) => i.status === "approved")
      : []
    : all;
  const reviewedImageIds = all.filter((i) => i.status === "reviewed").map((i) => i.id);
  const symptoms = problem.symptoms[lang] ?? [];

  const onProblemAction = (to: CorpusStatus) => {
    if (to === "approved" || to === "retired")
      setMove({
        kind: "problem",
        id: problem.id,
        from: problem.status,
        to,
        imageIds: to === "approved" ? reviewedImageIds : [],
      });
    else
      moveProblem.mutate(
        { id: problem.id, to, note: null },
        { onSuccess: () => toast.success(t("corpus.moved", { status: t(`corpus.status.${to}`) })) },
      );
  };
  const onImageAction = (img: CorpusImage, to: CorpusStatus) => {
    if (to === "approved" || to === "retired")
      setMove({ kind: "image", id: img.id, from: img.status, to, imageIds: [] });
    else
      moveImage.mutate(
        { id: img.id, to, note: null },
        { onSuccess: () => toast.success(t("corpus.moved", { status: t(`corpus.status.${to}`) })) },
      );
  };
  const inlineError = moveProblem.error ?? moveImage.error;

  return (
    <section
      className="flex flex-col gap-4 rounded-card border border-border bg-surface p-4"
      aria-labelledby="problem-heading"
      data-testid="problem-detail"
    >
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="problem-heading" className="text-heading font-semibold">
            {name} · {cropName}
          </h2>
          <span className="flex flex-wrap items-center gap-2 text-small text-text-secondary">
            <CorpusStatusChip status={problem.status} />
            {knownLabel(t, problem.problem_type, PROBLEM_TYPES, (x) => `corpus.type.${x}` as const)}
            {" · "}
            {knownLabel(t, problem.source, CORPUS_SOURCES, (s) => `corpus.source.${s}` as const)}
            {problem.approved_in_version ? (
              <span className="tnum">
                · {t("corpus.detail.approvedIn", { v: problem.approved_in_version })}
              </span>
            ) : null}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {canWrite && isEditable(problem.status) ? (
            <AppButton variant="secondary" icon={<Pencil aria-hidden="true" />} onClick={onEdit}>
              {t("corpus.edit")}
            </AppButton>
          ) : null}
          <AppButton variant="tertiary" onClick={onClose}>
            {t("corpus.detail.close")}
          </AppButton>
        </div>
      </header>

      <WorkflowButtons
        status={problem.status}
        onAction={onProblemAction}
        testId="problem-actions"
      />
      {!isEditable(problem.status) ? (
        <p className="flex items-center gap-2 text-small text-text-muted">
          <Info className="size-4" aria-hidden="true" />
          {t("corpus.locked")}
        </p>
      ) : null}
      {inlineError ? (
        <p role="alert" className="text-small text-danger">
          {corpusError(inlineError, t)}
        </p>
      ) : null}

      <div className="grid gap-4 md:grid-cols-2">
        <div className="flex flex-col gap-2">
          <dl
            className="grid grid-cols-[8rem_1fr] gap-x-3 gap-y-1 text-small"
            data-testid="problem-names"
          >
            {LOCALES.map((l) => (
              <div key={l} className="contents">
                <dt className="text-text-muted">{t(`language.${l}`)}</dt>
                <dd lang={l}>{problem.names[l] || t("common.none")}</dd>
              </div>
            ))}
          </dl>
          <dl className="grid grid-cols-[8rem_1fr] gap-x-3 gap-y-1 text-small">
            <dt className="text-text-muted">{t("corpus.detail.reviewedAt")}</dt>
            <dd className="tnum">
              {problem.reviewed_at ? formatDateTimeIst(problem.reviewed_at) : t("common.none")}
            </dd>
            <dt className="text-text-muted">{t("corpus.detail.approvedAt")}</dt>
            <dd className="tnum">
              {problem.approved_at ? formatDateTimeIst(problem.approved_at) : t("common.none")}
            </dd>
            {problem.retired_at ? (
              <>
                <dt className="text-text-muted">{t("corpus.detail.retiredAt")}</dt>
                <dd className="tnum">{formatDateTimeIst(problem.retired_at)}</dd>
              </>
            ) : null}
            {problem.notes ? (
              <>
                <dt className="text-text-muted">{t("corpus.detail.notes")}</dt>
                <dd>{problem.notes}</dd>
              </>
            ) : null}
          </dl>
        </div>
        <div className="flex flex-col gap-2">
          <SelectField
            label={t("language.label")}
            value={lang}
            onChange={(e) => setLang(e.target.value as Locale)}
            options={LOCALES.map((l) => ({ value: l, label: t(`language.${l}`) }))}
            className="max-w-48"
          />
          <h3 className="text-body font-semibold">
            {t("corpus.detail.symptoms", { lang: t(`language.${lang}`) })}
          </h3>
          {symptoms.length ? (
            <ul
              className="list-inside list-disc text-small"
              lang={lang}
              data-testid="problem-symptoms"
            >
              {symptoms.map((s) => (
                <li key={s}>{s}</li>
              ))}
            </ul>
          ) : (
            <p className="text-small text-text-muted">{t("corpus.detail.noSymptoms")}</p>
          )}
        </div>
      </div>

      <section className="flex flex-col gap-3" aria-labelledby="images-heading">
        <h3 id="images-heading" className="text-body font-semibold">
          {t("corpus.images.title")}
        </h3>
        {canWrite && problem.status !== "retired" ? <ImageUpload problemId={problem.id} /> : null}
        {images.isLoading ? (
          <Skeleton className="h-40 w-full" />
        ) : images.error ? (
          <QueryError error={images.error} onRetry={() => void images.refetch()} />
        ) : shown.length === 0 ? (
          <p className="text-small text-text-muted">{t("corpus.images.empty")}</p>
        ) : (
          <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3" data-testid="image-grid">
            {shown.map((img, i) => (
              <li
                key={img.id}
                className="flex flex-col gap-2 rounded-card border border-border p-2"
                data-testid="corpus-image"
                data-status={img.status}
              >
                {img.signed_url ? (
                  // eslint-disable-next-line @next/next/no-img-element -- short-lived signed URLs
                  <img
                    src={img.signed_url}
                    alt={t("corpus.images.alt", { problem: name, n: i + 1 })}
                    className="h-36 w-full rounded-input object-cover"
                  />
                ) : null}
                <span className="flex flex-wrap items-center gap-1.5">
                  <CorpusStatusChip status={img.status} />
                  {img.from_diagnosis_id ? (
                    <Badge variant="outline">{t("corpus.images.fromReview")}</Badge>
                  ) : null}
                </span>
                <span
                  className="flex items-center gap-1 text-small text-success"
                  data-testid="embedding-status"
                >
                  <Cpu className="size-4" aria-hidden="true" />
                  {t("corpus.images.embedded", {
                    encoder: `${img.encoder_name}@${img.encoder_version}`,
                  })}
                </span>
                <ImageMeta image={img} />
                <WorkflowButtons
                  status={img.status}
                  onAction={(to) => onImageAction(img, to)}
                  testId="image-actions"
                />
              </li>
            ))}
          </ul>
        )}
      </section>

      {move ? <MoveDialog move={move} version={version} onClose={() => setMove(null)} /> : null}
    </section>
  );
}

function ImageMeta({ image }: { image: CorpusImage }) {
  const t = useT();
  const rows: Array<[string, string]> = [
    [t("corpus.meta.stage"), knownLabel(t, image.stage, CROP_STAGES, (s) => `stage.${s}` as const)],
    [
      t("corpus.meta.part"),
      knownLabel(t, image.part, IMAGE_PARTS, (p) => `corpus.part.${p}` as const),
    ],
    [
      t("corpus.meta.severity"),
      knownLabel(t, image.severity, IMAGE_SEVERITIES, (s) => `severity.${s}` as const),
    ],
    [t("corpus.meta.region"), image.region ?? t("common.none")],
    [
      t("corpus.meta.season"),
      knownLabel(t, image.season, SEASONS, (s) => `corpus.season.${s}` as const),
    ],
    [
      t("corpus.meta.source"),
      knownLabel(t, image.source, CORPUS_SOURCES, (s) => `corpus.source.${s}` as const),
    ],
  ];
  return (
    <dl className="grid grid-cols-[5.5rem_1fr] gap-x-2 text-small" data-testid="image-meta">
      {rows.map(([k, v]) => (
        <div key={k} className="contents">
          <dt className="text-text-muted">{k}</dt>
          <dd>{v}</dd>
        </div>
      ))}
    </dl>
  );
}

function ImageUpload({ problemId }: { problemId: string }) {
  const t = useT();
  const upload = useUploadCorpusImage(problemId);
  const fileRef = React.useRef<HTMLInputElement>(null);
  const [file, setFile] = React.useState<File | null>(null);
  const [stage, setStage] = React.useState("");
  const [part, setPart] = React.useState<ImagePart | "">("leaf");
  const [severity, setSeverity] = React.useState<ImageSeverity | "">("");
  const [region, setRegion] = React.useState("");
  const [season, setSeason] = React.useState("");
  const [source, setSource] = React.useState<CorpusSource>("internal");
  const [progress, setProgress] = React.useState<{
    phase: "uploading" | "embedding";
    f: number;
  } | null>(null);
  const [fileError, setFileError] = React.useState(false);

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!file) {
      setFileError(true);
      return;
    }
    upload.mutate(
      {
        file,
        meta: {
          stage: stage || null,
          part: part || null,
          severity: severity || null,
          region: region.trim() || null,
          season: season || null,
          source,
        },
        onProgress: (phase, f) => setProgress({ phase, f }),
      },
      {
        onSettled: () => setProgress(null),
        onSuccess: () => {
          setFile(null);
          if (fileRef.current) fileRef.current.value = "";
          toast.success(t("corpus.moved", { status: t("corpus.status.draft") }));
        },
      },
    );
  };

  return (
    <form
      onSubmit={submit}
      noValidate
      className="flex flex-col gap-3 rounded-card border border-dashed border-border p-3"
      data-testid="image-upload"
    >
      <div className="flex flex-col gap-1">
        <label
          htmlFor={`${problemId}-file`}
          className="text-small font-semibold text-text-secondary"
        >
          {t("corpus.images.file")}
        </label>
        <input
          ref={fileRef}
          id={`${problemId}-file`}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          onChange={(e) => {
            setFile(e.target.files?.[0] ?? null);
            setFileError(false);
          }}
          className="text-small"
        />
        <p className="text-small text-text-muted">{t("corpus.images.uploadHelp")}</p>
        {fileError ? (
          <p role="alert" className="text-small text-danger">
            {t("corpus.images.fileRequired")}
          </p>
        ) : null}
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <SelectField
          label={t("corpus.meta.stage")}
          value={stage}
          onChange={(e) => setStage(e.target.value)}
          emptyLabel={t("common.none")}
          options={CROP_STAGES.map((s) => ({ value: s, label: t(`stage.${s}`) }))}
        />
        <SelectField
          label={t("corpus.meta.part")}
          value={part}
          onChange={(e) => setPart(e.target.value as ImagePart | "")}
          emptyLabel={t("common.none")}
          options={IMAGE_PARTS.map((p) => ({ value: p, label: t(`corpus.part.${p}`) }))}
        />
        <SelectField
          label={t("corpus.meta.severity")}
          value={severity}
          onChange={(e) => setSeverity(e.target.value as ImageSeverity | "")}
          emptyLabel={t("common.none")}
          options={IMAGE_SEVERITIES.map((s) => ({ value: s, label: t(`severity.${s}`) }))}
        />
        <AppTextField
          label={t("corpus.meta.region")}
          value={region}
          maxLength={80}
          onChange={(e) => setRegion(e.target.value)}
          optional
        />
        <SelectField
          label={t("corpus.meta.season")}
          value={season}
          onChange={(e) => setSeason(e.target.value)}
          emptyLabel={t("common.none")}
          options={SEASONS.map((s) => ({ value: s, label: t(`corpus.season.${s}`) }))}
        />
        <SelectField
          label={t("corpus.meta.source")}
          value={source}
          onChange={(e) => setSource(e.target.value as CorpusSource)}
          options={CORPUS_SOURCES.map((s) => ({ value: s, label: t(`corpus.source.${s}`) }))}
        />
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <AppButton
          type="submit"
          variant="secondary"
          icon={<Upload aria-hidden="true" />}
          loading={upload.isPending}
        >
          {t("corpus.images.upload")}
        </AppButton>
        {progress ? (
          <span
            className="tnum text-small text-text-secondary"
            role="status"
            data-testid="upload-progress"
          >
            {progress.phase === "uploading"
              ? t("corpus.images.uploading", { pct: Math.round(progress.f * 100) })
              : t("corpus.images.embedding")}
          </span>
        ) : null}
        {upload.error ? (
          <p role="alert" className="text-small text-danger">
            {corpusError(upload.error, t)}
          </p>
        ) : null}
      </div>
    </form>
  );
}

// ---- versions ----------------------------------------------------------------------------
function VersionHistory() {
  const t = useT();
  const versions = useCorpusVersions();
  const items = versions.data?.items ?? [];
  return (
    <section
      className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
      aria-labelledby="versions-heading"
      data-testid="version-history"
    >
      <h2 id="versions-heading" className="text-heading font-semibold">
        {t("corpus.versions.title")}
      </h2>
      {versions.isLoading ? (
        <Skeleton className="h-24 w-full" />
      ) : versions.error ? (
        <QueryError error={versions.error} onRetry={() => void versions.refetch()} />
      ) : items.length === 0 ? (
        <p className="text-small text-text-muted">{t("corpus.versions.empty")}</p>
      ) : (
        <ol className="flex flex-col divide-y divide-border">
          {items.slice(0, 20).map((v) => (
            <li
              key={v.id}
              className="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-2 text-small"
              data-testid="version-row"
            >
              <span className="tnum font-semibold">{`v${v.version}`}</span>
              {v.version === versions.data?.current ? (
                <Badge variant="success">{t("corpus.versions.current")}</Badge>
              ) : null}
              <span className="tnum text-text-muted">{formatDateTimeIst(v.created_at)}</span>
              <span className="tnum text-text-secondary">
                {t("corpus.versions.changes", {
                  p: v.changes.problems?.length ?? 0,
                  i: v.changes.images?.length ?? 0,
                  r: v.changes.retired?.length ?? 0,
                })}
              </span>
              {v.note ? <span className="text-text">{v.note}</span> : null}
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
