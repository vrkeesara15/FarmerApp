"use client";

/**
 * C60 review form (WC-006): confirm the label, correct it (problem picker limited to the
 * diagnosis's crop, searchable in every language), or mark it not diagnosable; a note for the
 * record and "add these photos to the corpus". Validation mirrors `ReviewIn`.
 */
import * as React from "react";
import { AppButton } from "@/components/ds/AppButton";
import { CheckboxField, TextAreaField } from "@/components/admin/common";
import { matchesProblem, type CorpusProblem } from "@/lib/corpus";
import {
  localName,
  reviewBody,
  validateReview,
  type ReviewAction,
  type ReviewDraft,
  type ReviewErrors,
  type ReviewInput,
} from "@/lib/diagnosis";
import { useLocale, useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";
import { CorpusStatusChip } from "./common";

const ACTION_KEYS = {
  confirm: "review.form.confirm",
  correct: "review.form.correct",
  not_diagnosable: "review.form.notDiagnosable",
} as const;

export function ProblemPicker({
  problems,
  value,
  onChange,
  cropName,
  error,
}: {
  problems: ReadonlyArray<CorpusProblem>;
  value: string;
  onChange: (id: string) => void;
  cropName: string;
  error?: string;
}) {
  const t = useT();
  const locale = useLocale();
  const [q, setQ] = React.useState("");
  const id = React.useId();
  const shown = problems.filter((p) => matchesProblem(p, q));
  return (
    <fieldset className="flex flex-col gap-2" aria-describedby={`${id}-help`}>
      <legend className="text-small font-semibold text-text-secondary">
        {t("review.form.problem")}
      </legend>
      <input
        type="search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        aria-label={t("review.form.search")}
        placeholder={t("review.form.search")}
        className="h-10 rounded-input border border-border bg-surface px-3 text-body focus:outline-none focus:ring-2 focus:ring-primary"
      />
      <p id={`${id}-help`} className="text-small text-text-muted">
        {t("review.form.problemHelp", { crop: cropName })}
      </p>
      <div
        role="radiogroup"
        aria-label={t("review.form.problem")}
        aria-invalid={error ? true : undefined}
        className="flex max-h-56 flex-col gap-1 overflow-y-auto"
        data-testid="problem-picker"
      >
        {shown.length === 0 ? (
          <p className="text-small text-text-secondary">{t("review.form.noProblems")}</p>
        ) : (
          shown.map((p) => {
            const name = localName(p.names, locale, p.pest_code ?? p.id);
            const other = locale === "en" ? null : p.names.en;
            return (
              <label
                key={p.id}
                className={cn(
                  "flex cursor-pointer items-center gap-2 rounded-input border px-2 py-1.5 text-body",
                  value === p.id ? "border-primary bg-primary-container" : "border-border",
                )}
              >
                <input
                  type="radio"
                  name={`${id}-problem`}
                  value={p.id}
                  checked={value === p.id}
                  onChange={() => onChange(p.id)}
                  className="accent-primary"
                />
                <span className="flex-1">
                  {name}
                  {other && other !== name ? (
                    <span className="ml-1 text-small text-text-muted">({other})</span>
                  ) : null}
                </span>
                <CorpusStatusChip status={p.status} />
              </label>
            );
          })
        )}
      </div>
      {error ? (
        <p role="alert" className="text-small text-danger">
          {error}
        </p>
      ) : null}
    </fieldset>
  );
}

export function ReviewForm({
  cropProblems,
  currentProblemId,
  cropName,
  canAddPhotos,
  submitting,
  error,
  onSubmit,
}: {
  /** Live corpus problems of the diagnosis's crop. */
  cropProblems: ReadonlyArray<CorpusProblem>;
  currentProblemId: string | null;
  cropName: string;
  canAddPhotos: boolean;
  submitting?: boolean;
  error?: string;
  onSubmit: (body: ReviewInput) => void;
}) {
  const t = useT();
  const [draft, setDraft] = React.useState<ReviewDraft>({
    action: "",
    problemId: "",
    note: "",
    addToCorpus: false,
  });
  const [errors, setErrors] = React.useState<ReviewErrors>({});
  const [tried, setTried] = React.useState(false);
  const set = (patch: Partial<ReviewDraft>) => {
    const next = { ...draft, ...patch };
    setDraft(next);
    if (tried) setErrors(validateReview(next, currentProblemId));
  };
  const actions: ReviewAction[] = currentProblemId
    ? ["confirm", "correct", "not_diagnosable"]
    : ["correct", "not_diagnosable"];

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    setTried(true);
    const errs = validateReview(draft, currentProblemId);
    setErrors(errs);
    if (Object.keys(errs).length === 0) onSubmit(reviewBody(draft));
  };

  const problemError =
    errors.problem === "required"
      ? t("review.form.errors.problem")
      : errors.problem === "same"
        ? t("review.form.errors.same")
        : undefined;

  return (
    <form
      onSubmit={submit}
      noValidate
      className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4"
      aria-labelledby="review-form-heading"
      data-testid="review-form"
    >
      <h3 id="review-form-heading" className="text-heading font-semibold">
        {t("review.form.title")}
      </h3>
      <fieldset className="flex flex-col gap-1">
        <legend className="text-small font-semibold text-text-secondary">
          {t("review.form.action")}
        </legend>
        <div className="flex flex-wrap gap-3">
          {actions.map((a) => (
            <label key={a} className="flex items-center gap-2 text-body">
              <input
                type="radio"
                name="review-action"
                value={a}
                checked={draft.action === a}
                onChange={() => set({ action: a })}
                className="accent-primary"
              />
              {t(ACTION_KEYS[a])}
            </label>
          ))}
        </div>
        {!currentProblemId ? (
          <p className="text-small text-text-muted">{t("review.form.nothingToConfirm")}</p>
        ) : null}
        {errors.action ? (
          <p role="alert" className="text-small text-danger">
            {t("review.form.errors.action")}
          </p>
        ) : null}
      </fieldset>
      {draft.action === "correct" ? (
        <ProblemPicker
          problems={cropProblems}
          value={draft.problemId}
          onChange={(problemId) => set({ problemId })}
          cropName={cropName}
          error={problemError}
        />
      ) : null}
      <TextAreaField
        label={t("review.form.note")}
        value={draft.note}
        maxLength={2000}
        onChange={(e) => set({ note: e.target.value })}
        error={errors.note ? t("review.form.errors.note") : undefined}
      />
      {canAddPhotos && draft.action !== "not_diagnosable" ? (
        <CheckboxField
          label={t("review.form.addToCorpus")}
          checked={draft.addToCorpus}
          onChange={(e) => set({ addToCorpus: e.target.checked })}
        />
      ) : null}
      {error ? (
        <p role="alert" className="text-small text-danger" data-testid="review-error">
          {error}
        </p>
      ) : null}
      <div>
        <AppButton type="submit" loading={submitting}>
          {t("review.form.submit")}
        </AppButton>
      </div>
    </form>
  );
}
