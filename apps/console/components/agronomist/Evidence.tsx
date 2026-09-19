"use client";

/**
 * C60 evidence blocks: model candidates with similarity and vote share (DX-003), the LLM's
 * answer and reasoning labelled "Automated suggestion — verify" (DX-004), and the provenance
 * record (DX-005: encoder, on-device model, LLM model, corpus version, source).
 */
import { Bot } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  CONFIDENCES,
  candidateRows,
  formatScore,
  localName,
  type Diagnosis,
  type LocalisedProblem,
} from "@/lib/diagnosis";
import { formatPercent } from "@/lib/format";
import { useLocale, useT } from "@/lib/i18n-client";
import { knownLabel } from "./common";

type NameOf = (problemId: string | null | undefined) => string;

export function CandidateTable({
  diagnosis,
  nameOf,
}: {
  diagnosis: Pick<Diagnosis, "scores">;
  nameOf: NameOf;
}) {
  const t = useT();
  const rows = candidateRows(diagnosis.scores);
  const th = diagnosis.scores?.thresholds;
  return (
    <section
      className="flex flex-col gap-2"
      aria-labelledby="cand-heading"
      data-testid="candidates"
    >
      <h3 id="cand-heading" className="text-body font-semibold">
        {t("review.candidates.title")}
      </h3>
      {rows.length === 0 ? (
        <p className="text-small text-text-secondary">{t("review.candidates.none")}</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-small">
            <thead>
              <tr className="border-b border-border text-left text-text-muted">
                <th scope="col" className="py-1 pr-2 font-semibold">
                  {t("review.candidates.problem")}
                </th>
                <th scope="col" className="py-1 pr-2 text-right font-semibold">
                  {t("review.candidates.similarity")}
                </th>
                <th scope="col" className="py-1 pr-2 text-right font-semibold">
                  {t("review.candidates.votes")}
                </th>
                <th scope="col" className="py-1 font-semibold">
                  {t("review.candidates.share")}
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr
                  key={r.problemId}
                  className="border-b border-border"
                  data-testid="candidate-row"
                >
                  <td className="py-1.5 pr-2">
                    <span className="flex flex-wrap items-center gap-1">
                      <span data-testid="candidate-name">{nameOf(r.problemId)}</span>
                      {r.proposed ? (
                        <Badge variant="default">{t("review.candidates.corpusPick")}</Badge>
                      ) : null}
                      {r.llmChoice ? (
                        <Badge variant="info">{t("review.candidates.llmPick")}</Badge>
                      ) : null}
                    </span>
                  </td>
                  <td className="tnum py-1.5 pr-2 text-right" data-testid="candidate-score">
                    {formatScore(r.score)}
                  </td>
                  <td className="tnum py-1.5 pr-2 text-right">{r.votes}</td>
                  <td className="py-1.5">
                    <span className="flex items-center gap-2">
                      <span
                        className="h-2 w-20 overflow-hidden rounded-pill bg-background"
                        aria-hidden="true"
                      >
                        <span
                          className="block h-full bg-primary"
                          style={{ width: `${Math.round(r.voteShare * 100)}%` }}
                        />
                      </span>
                      <span className="tnum" data-testid="candidate-share">
                        {formatPercent(r.voteShare, 0)}
                      </span>
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {th ? (
        <p className="tnum text-small text-text-muted" data-testid="thresholds">
          {t("review.candidates.thresholds", {
            v: th.config_version,
            t1: th.t1.toFixed(2),
            agreement: formatPercent(th.agreement, 0),
            floor: th.min_similarity.toFixed(2),
          })}
        </p>
      ) : null}
    </section>
  );
}

export function LlmAnswer({ diagnosis, nameOf }: { diagnosis: Diagnosis; nameOf: NameOf }) {
  const t = useT();
  const llm = diagnosis.scores?.llm;
  const symptoms = diagnosis.result?.visible_symptoms ?? [];
  return (
    <section
      className="bg-info-container/40 flex flex-col gap-2 rounded-card border border-dashed border-info p-3"
      aria-labelledby="llm-heading"
      data-testid="llm-answer"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 id="llm-heading" className="flex items-center gap-2 text-body font-semibold">
          <Bot className="size-5" aria-hidden="true" />
          {t("review.llm.title")}
        </h3>
        <Badge variant="info" data-testid="llm-label">
          {t("review.llm.label")}
        </Badge>
      </div>
      {!llm ? (
        <p className="text-small text-text-secondary">{t("review.llm.notUsed")}</p>
      ) : (
        <dl className="grid gap-2 text-small sm:grid-cols-[10rem_1fr]">
          <dt className="text-text-muted">{t("review.llm.answer")}</dt>
          <dd data-testid="llm-choice">
            {llm.not_a_plant
              ? t("review.llm.notAPlant")
              : llm.problem_id
                ? nameOf(llm.problem_id)
                : t("review.llm.unknown")}
          </dd>
          <dt className="text-text-muted">{t("review.llm.confidence")}</dt>
          <dd>{knownLabel(t, llm.confidence, CONFIDENCES, (c) => `confidence.${c}` as const)}</dd>
          {llm.reasoning ? (
            <>
              <dt className="text-text-muted">{t("review.llm.reasoning")}</dt>
              <dd data-testid="llm-reasoning">{llm.reasoning}</dd>
            </>
          ) : null}
          {symptoms.length ? (
            <>
              <dt className="text-text-muted">{t("review.llm.symptoms")}</dt>
              <dd>{symptoms.join(", ")}</dd>
            </>
          ) : null}
        </dl>
      )}
    </section>
  );
}

export function ProvenanceBlock({ diagnosis }: { diagnosis: Diagnosis }) {
  const t = useT();
  const mv = diagnosis.model_versions ?? {};
  const none = t("review.provenance.notUsed");
  const source = diagnosis.source;
  const rows: Array<[string, string]> = [
    [
      t("review.provenance.source"),
      source && ["corpus", "llm", "agronomist"].includes(source)
        ? t(`queue.source.${source as "corpus" | "llm" | "agronomist"}`)
        : t("queue.source.none"),
    ],
    [t("review.provenance.encoder"), mv.encoder || none],
    [t("review.provenance.onDevice"), mv.on_device || none],
    [t("review.provenance.llm"), mv.llm || none],
    [
      t("review.provenance.corpus"),
      diagnosis.corpus_version === null ? none : String(diagnosis.corpus_version),
    ],
  ];
  return (
    <section
      className="flex flex-col gap-2"
      aria-labelledby="prov-heading"
      data-testid="provenance"
    >
      <h3 id="prov-heading" className="text-body font-semibold">
        {t("review.provenance.title")}
      </h3>
      <dl className="grid grid-cols-[10rem_1fr] gap-x-3 gap-y-1 text-small">
        {rows.map(([k, v]) => (
          <div key={k} className="contents">
            <dt className="text-text-muted">{k}</dt>
            <dd className="break-all font-mono text-text">{v}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

/** Name of a problem from the corpus index, else the result's embedded problem. */
export function makeNameOf(
  index: Map<string, { names: Record<string, string>; pest_code: string | null }>,
  locale: string,
  embedded?: LocalisedProblem | null,
  fallback = "",
): NameOf {
  return (id) => {
    if (!id) return fallback;
    const p = index.get(id);
    if (p) return localName(p.names, locale, p.pest_code ?? id);
    if (embedded && embedded.id === id) return localName(embedded.names, locale, embedded.code);
    return id.slice(0, 8);
  };
}

export function useNameOf(
  index: Map<string, { names: Record<string, string>; pest_code: string | null }>,
  embedded?: LocalisedProblem | null,
): NameOf {
  const locale = useLocale();
  const t = useT();
  return makeNameOf(index, locale, embedded, t("queue.noLabel"));
}
