"use client";

/**
 * C61 create / edit corpus problem (WC-007, SPEC 3.2): crop and pest or disease from the product
 * master (the type follows the pest), names in the five launch languages, the symptom checklist
 * and cultural practices per language (one per line), source and notes. Only draft and reviewed
 * entries can be edited (approved / retired are locked).
 */
import * as React from "react";
import { AppTextField } from "@/components/ds/AppTextField";
import { Dialog } from "@/components/ds/Dialog";
import { SegmentedControl } from "@/components/ds/SegmentedControl";
import { SelectField, TextAreaField } from "@/components/admin/common";
import {
  CORPUS_SOURCES,
  PROBLEM_TYPES,
  compactLists,
  compactNames,
  type CorpusProblem,
  type CorpusProblemInput,
  type CorpusSource,
} from "@/lib/corpus";
import { localName } from "@/lib/diagnosis";
import { useCrops, usePests } from "@/lib/hooks/catalog";
import { useCreateProblem, useUpdateProblem } from "@/lib/hooks/diagnosis";
import { LOCALES, type Locale } from "@/lib/i18n";
import { useLocale, useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { knownLabel } from "./common";

type PerLang = Record<Locale, string>;
const empty = (): PerLang => ({ en: "", te: "", kn: "", hi: "", mr: "" });
const fromLists = (m: Record<string, string[]> | undefined): PerLang => {
  const out = empty();
  for (const l of LOCALES) out[l] = (m?.[l] ?? []).join("\n");
  return out;
};

export function ProblemDialog({
  open,
  onOpenChange,
  problem,
  existing,
  defaultCropId,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** The problem to edit; create when null. */
  problem: CorpusProblem | null;
  /** Live entries, to hide crop + pest pairs that already exist. */
  existing: ReadonlyArray<CorpusProblem>;
  defaultCropId?: string;
  onSaved: (p: CorpusProblem) => void;
}) {
  const t = useT();
  const locale = useLocale();
  const crops = useCrops();
  const create = useCreateProblem();
  const update = useUpdateProblem();
  const [cropId, setCropId] = React.useState(problem?.crop_id ?? defaultCropId ?? "");
  const pests = usePests(cropId || undefined);
  const [pestId, setPestId] = React.useState(problem?.pest_or_disease_id ?? "");
  const [lang, setLang] = React.useState<Locale>("en");
  const [names, setNames] = React.useState<PerLang>(() => ({
    ...empty(),
    ...(problem?.names ?? {}),
  }));
  const [symptoms, setSymptoms] = React.useState<PerLang>(() => fromLists(problem?.symptoms));
  const [practices, setPractices] = React.useState<PerLang>(() =>
    fromLists(problem?.cultural_practices),
  );
  const [source, setSource] = React.useState<CorpusSource>(
    (problem?.source as CorpusSource) ?? "internal",
  );
  const [notes, setNotes] = React.useState(problem?.notes ?? "");
  const [errors, setErrors] = React.useState<Partial<Record<"crop" | "pest" | "name", string>>>({});

  const taken = new Set(
    existing
      .filter((p) => p.crop_id === cropId && p.status !== "retired" && p.id !== problem?.id)
      .map((p) => p.pest_or_disease_id),
  );
  const pestOptions = (pests.data ?? []).filter((p) => !taken.has(p.id));
  const pest = (pests.data ?? []).find((p) => p.id === pestId);
  const type = problem?.problem_type ?? pest?.type;
  const missing = LOCALES.filter((l) => !names[l].trim()).map((l) => t(`language.${l}`));
  const mutation = problem ? update : create;

  const save = () => {
    const errs: typeof errors = {};
    if (!problem && !cropId) errs.crop = t("corpus.dialog.cropRequired");
    if (!problem && !pestId) errs.pest = t("corpus.dialog.pestRequired");
    if (!names.en.trim()) errs.name = t("corpus.dialog.nameRequired");
    setErrors(errs);
    if (errs.name) setLang("en");
    if (Object.keys(errs).length) return;
    const common = {
      names: compactNames(names),
      symptoms: compactLists(symptoms),
      cultural_practices: compactLists(practices),
      notes: notes.trim() || null,
    };
    if (problem) update.mutate({ id: problem.id, body: common }, { onSuccess: (p) => onSaved(p) });
    else {
      const body: CorpusProblemInput = {
        ...common,
        pest_or_disease_id: pestId,
        crop_id: cropId,
        source,
      };
      create.mutate(body, { onSuccess: (p) => onSaved(p) });
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={
        problem
          ? t("corpus.dialog.editTitle", {
              name: localName(problem.names, locale, problem.pest_code ?? ""),
            })
          : t("corpus.dialog.createTitle")
      }
      confirmLabel={t("common.save")}
      onConfirm={save}
      loading={mutation.isPending}
      error={mutation.error ? problemMessage(mutation.error, t) : undefined}
      className="max-h-[90vh] max-w-2xl overflow-y-auto"
    >
      <div className="flex flex-col gap-3" data-testid="problem-dialog">
        {!problem ? (
          <div className="grid gap-3 sm:grid-cols-2">
            <SelectField
              label={t("corpus.dialog.crop")}
              value={cropId}
              onChange={(e) => {
                setCropId(e.target.value);
                setPestId("");
              }}
              emptyLabel=""
              options={(crops.data ?? []).map((c) => ({
                value: c.id,
                label: localName(c.names, locale, c.name),
              }))}
              error={errors.crop}
            />
            <div className="flex flex-col gap-1">
              <SelectField
                label={t("corpus.dialog.pest")}
                value={pestId}
                onChange={(e) => setPestId(e.target.value)}
                emptyLabel=""
                disabled={!cropId}
                options={pestOptions.map((p) => ({
                  value: p.id,
                  label: localName(p.names, locale, p.name),
                }))}
                error={errors.pest}
              />
              <p className="text-small text-text-muted">{t("corpus.dialog.pestHelp")}</p>
            </div>
          </div>
        ) : null}
        {type ? (
          <p className="text-small text-text-secondary" data-testid="problem-type">
            {t("corpus.dialog.type", {
              type: knownLabel(t, type, PROBLEM_TYPES, (x) => `corpus.type.${x}` as const),
            })}
          </p>
        ) : null}
        <SegmentedControl
          label={t("language.label")}
          value={lang}
          onChange={setLang}
          size="sm"
          options={LOCALES.map((l) => ({ value: l, label: t(`language.${l}`) }))}
        />
        <AppTextField
          label={t("corpus.dialog.nameIn", { lang: t(`language.${lang}`) })}
          value={names[lang]}
          onChange={(e) => setNames({ ...names, [lang]: e.target.value })}
          error={lang === "en" ? errors.name : undefined}
          optional={lang !== "en"}
        />
        <TextAreaField
          label={t("corpus.dialog.symptomsIn", { lang: t(`language.${lang}`) })}
          value={symptoms[lang]}
          rows={3}
          onChange={(e) => setSymptoms({ ...symptoms, [lang]: e.target.value })}
          optional
        />
        <TextAreaField
          label={t("corpus.dialog.practicesIn", { lang: t(`language.${lang}`) })}
          value={practices[lang]}
          onChange={(e) => setPractices({ ...practices, [lang]: e.target.value })}
          optional
        />
        {missing.length ? (
          <p className="text-small text-warning" data-testid="missing-langs">
            {t("corpus.dialog.missing", { langs: missing.join(", ") })}
          </p>
        ) : null}
        {!problem ? (
          <SelectField
            label={t("corpus.dialog.source")}
            value={source}
            onChange={(e) => setSource(e.target.value as CorpusSource)}
            options={CORPUS_SOURCES.map((s) => ({ value: s, label: t(`corpus.source.${s}`) }))}
          />
        ) : null}
        <TextAreaField
          label={t("corpus.dialog.notes")}
          value={notes}
          maxLength={4000}
          onChange={(e) => setNotes(e.target.value)}
          optional
        />
      </div>
    </Dialog>
  );
}
