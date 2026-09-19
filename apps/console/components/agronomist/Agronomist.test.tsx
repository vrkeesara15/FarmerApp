import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { CorpusProblem } from "@/lib/corpus";
import type { Diagnosis } from "@/lib/diagnosis";
import { CandidateTable, LlmAnswer, ProvenanceBlock, makeNameOf } from "./Evidence";
import { ReviewForm } from "./ReviewForm";

const problem = (
  id: string,
  en: string,
  te: string,
  status: CorpusProblem["status"] = "approved",
) =>
  ({
    id,
    pest_or_disease_id: `pest-${id}`,
    pest_code: id,
    crop_id: "crop-paddy",
    problem_type: "disease",
    names: { en, te },
    symptoms: {},
    cultural_practices: {},
    status,
    source: "internal",
    image_counts: {},
  }) as unknown as CorpusProblem;

const PROBLEMS = [
  problem("blast", "Rice blast", "అగ్గి తెగులు"),
  problem("zinc", "Zinc deficiency", "జింక్ లోపం"),
  problem("aphids", "Aphids", "పేనుబంక", "reviewed"),
];
const index = new Map(PROBLEMS.map((p) => [p.id, p]));
const nameOf = makeNameOf(index, "en", null, "No label yet");

const diagnosis = {
  status: "provisional",
  source: "llm",
  model_versions: {
    encoder: "siglip-base-patch16-224@2024-01",
    on_device: "ondevice-v1.0",
    llm: "claude-opus-5",
  },
  corpus_version: 7,
  result: { problem: null, visible_symptoms: ["grey lesions"] },
  scores: {
    votes: { blast: 6, zinc: 4 },
    decision: { problem_id: "blast" },
    thresholds: { t1: 0.92, agreement: 0.6, min_similarity: 0.85, config_version: 2 },
    candidates: [
      { problem_id: "zinc", score: 0.897, votes: 4 },
      { problem_id: "blast", score: 0.912, votes: 6 },
    ],
    llm: {
      problem_id: "blast",
      confidence: "medium",
      reasoning: "Spindle-shaped lesions with grey centres.",
      status: "answered",
    },
  },
} as unknown as Diagnosis;

describe("C60 evidence", () => {
  it("renders candidates with similarity, votes and vote share, best first", () => {
    render(<CandidateTable diagnosis={diagnosis} nameOf={nameOf} />);
    const rows = screen.getAllByTestId("candidate-row");
    expect(rows).toHaveLength(2);
    expect(within(rows[0]!).getByTestId("candidate-name")).toHaveTextContent("Rice blast");
    expect(within(rows[0]!).getByTestId("candidate-score")).toHaveTextContent("0.912");
    expect(within(rows[0]!).getByTestId("candidate-share")).toHaveTextContent("60%");
    expect(within(rows[0]!).getByText("Corpus pick")).toBeInTheDocument();
    expect(within(rows[0]!).getByText("LLM pick")).toBeInTheDocument();
    expect(within(rows[1]!).getByTestId("candidate-share")).toHaveTextContent("40%");
    expect(screen.getByTestId("thresholds")).toHaveTextContent(
      "Thresholds v2: T1 0.92 · agreement 60% · floor 0.85",
    );
  });

  it("explains an empty candidate list", () => {
    render(<CandidateTable diagnosis={{ scores: { candidates: [] } }} nameOf={nameOf} />);
    expect(screen.getByText(/No corpus candidates/)).toBeInTheDocument();
  });

  it("labels the LLM answer as an automated suggestion and shows the provenance", () => {
    render(
      <>
        <LlmAnswer diagnosis={diagnosis} nameOf={nameOf} />
        <ProvenanceBlock diagnosis={diagnosis} />
      </>,
    );
    expect(screen.getByTestId("llm-label")).toHaveTextContent("Automated suggestion — verify");
    expect(screen.getByTestId("llm-choice")).toHaveTextContent("Rice blast");
    expect(screen.getByTestId("llm-reasoning")).toHaveTextContent("Spindle-shaped");
    const prov = screen.getByTestId("provenance");
    for (const text of [
      "siglip-base-patch16-224@2024-01",
      "ondevice-v1.0",
      "claude-opus-5",
      "7",
      "LLM",
    ])
      expect(within(prov).getByText(text)).toBeInTheDocument();
  });
});

describe("C60 provenance: on-device block and ask-expert note", () => {
  it("shows the on-device scores, time and the note when present", () => {
    render(
      <ProvenanceBlock
        diagnosis={{
          ...diagnosis,
          on_device: {
            model: "crop_quality",
            model_version: "ondevice-v1.0",
            plant_score: 0.998,
            quality: { ok: 0.97, blurry: 0.02, dark: 0.01 },
            crop_scores: { paddy: 0.93, cotton: 0.01 },
            latency_ms: 38,
          },
          expert_note: "Spots spread to the next field",
        }}
      />,
    );
    const prov = screen.getByTestId("provenance");
    expect(
      within(prov).getByText("plant 1.00 · photo quality 0.97 · paddy 0.93"),
    ).toBeInTheDocument();
    expect(within(prov).getByText("38 ms")).toBeInTheDocument();
    expect(within(prov).getByText("Spots spread to the next field")).toBeInTheDocument();
  });

  it("leaves the rows out without an on-device block", () => {
    render(<ProvenanceBlock diagnosis={diagnosis} />);
    const prov = screen.getByTestId("provenance");
    expect(within(prov).queryByText("On-device scores")).toBeNull();
    expect(within(prov).queryByText("Ask-expert note")).toBeNull();
  });
});

describe("C60 review form validation", () => {
  const setup = (currentProblemId: string | null = "blast") => {
    const onSubmit = vi.fn();
    render(
      <ReviewForm
        cropProblems={PROBLEMS}
        currentProblemId={currentProblemId}
        cropName="Paddy"
        canAddPhotos
        onSubmit={onSubmit}
      />,
    );
    return { onSubmit, user: userEvent.setup() };
  };

  it("needs a decision and a note", async () => {
    const { onSubmit, user } = setup();
    await user.click(screen.getByRole("button", { name: "Submit review" }));
    expect(screen.getByText("Choose a decision.")).toBeInTheDocument();
    expect(screen.getByText("Add a note.")).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("correct requires a problem; the picker searches local names", async () => {
    const { onSubmit, user } = setup();
    await user.click(screen.getByLabelText("Correct label"));
    await user.type(screen.getByLabelText("Note for the record"), "Rusty spots, not blast");
    await user.click(screen.getByRole("button", { name: "Submit review" }));
    expect(screen.getByText("Pick the correct problem.")).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();

    await user.type(screen.getByLabelText("Search problems in any language"), "జింక్");
    const picker = screen.getByTestId("problem-picker");
    expect(within(picker).getAllByRole("radio")).toHaveLength(1);
    await user.click(within(picker).getByRole("radio"));
    await user.click(screen.getByLabelText(/Add these photos to the corpus/));
    await user.click(screen.getByRole("button", { name: "Submit review" }));
    expect(onSubmit).toHaveBeenCalledWith({
      action: "correct",
      problem_id: "zinc",
      note: "Rusty spots, not blast",
      add_to_corpus: true,
    });
  });

  it("refuses to 'correct' to the current label", async () => {
    const { onSubmit, user } = setup();
    await user.click(screen.getByLabelText("Correct label"));
    await user.click(within(screen.getByTestId("problem-picker")).getByLabelText(/Rice blast/));
    await user.type(screen.getByLabelText("Note for the record"), "x");
    await user.click(screen.getByRole("button", { name: "Submit review" }));
    expect(screen.getByText(/Pick a problem other than the current label/)).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("offers no 'confirm' without a label and never adds not-diagnosable photos", async () => {
    const { onSubmit, user } = setup(null);
    expect(screen.queryByLabelText("Confirm label")).not.toBeInTheDocument();
    await user.click(screen.getByLabelText("Not diagnosable"));
    expect(screen.queryByLabelText(/Add these photos/)).not.toBeInTheDocument();
    await user.type(screen.getByLabelText("Note for the record"), "Photo too blurry");
    await user.click(screen.getByRole("button", { name: "Submit review" }));
    expect(onSubmit).toHaveBeenCalledWith({
      action: "not_diagnosable",
      problem_id: null,
      note: "Photo too blurry",
      add_to_corpus: false,
    });
  });
});
