import { describe, expect, it } from "vitest";
import {
  accuracyTrend,
  bandFor,
  outbreakCells,
  rollupByDistrict,
  trendCrops,
  weekKeyOf,
  weekKeys,
  type CropHealthCell,
  type EvaluationRun,
} from "./mlops";

function cell(over: Partial<CropHealthCell>): CropHealthCell {
  return {
    district: "Warangal",
    crop_id: "crop-cotton",
    crop_code: "cotton",
    crop_names: { en: "Cotton" },
    problem_id: "p1",
    problem_code: "pink_bollworm",
    problem_type: "pest",
    problem_names: { en: "Pink bollworm" },
    iso_year: 2026,
    iso_week: 38,
    week_start: "2026-09-14",
    confirmed_cases: 4,
    farmers_affected: 3,
    prior_mean: 1.5,
    outbreak: false,
    alert_id: null,
    latitude: 17.97,
    longitude: 79.59,
    ...over,
  };
}

describe("AN-006 crop health rollup", () => {
  const items = [
    cell({ confirmed_cases: 14, farmers_affected: 11, outbreak: true, alert_id: "a1" }),
    cell({ problem_code: "leaf_spot", confirmed_cases: 3, farmers_affected: 2 }),
    cell({ district: "Karimnagar", confirmed_cases: 6, farmers_affected: 5 }),
    cell({ iso_week: 37, week_start: "2026-09-07", confirmed_cases: 2, farmers_affected: 2 }),
  ];

  it("lists ISO weeks newest first", () => {
    expect(weekKeys(items)).toEqual(["2026-W38", "2026-W37"]);
    expect(weekKeyOf(items[0]!)).toBe("2026-W38");
  });

  it("sums cases and farmers per district for one week, biggest first", () => {
    const rows = rollupByDistrict(items, "2026-W38");
    expect(rows.map((r) => r.district)).toEqual(["Warangal", "Karimnagar"]);
    expect(rows[0]).toMatchObject({ cases: 17, farmers: 13, outbreaks: 1 });
    expect(rows[0]!.cells).toHaveLength(2);
    expect(rows[1]).toMatchObject({ cases: 6, outbreaks: 0 });
  });

  it("keeps the district centroid for the markers (never a farm location)", () => {
    const rows = rollupByDistrict(items, "2026-W38");
    expect(rows[0]!.latitude).toBe(17.97);
    expect(rows[0]!.longitude).toBe(79.59);
  });

  it("rolls up every week when no week is chosen", () => {
    expect(rollupByDistrict(items, undefined)[0]!.cases).toBe(19);
  });

  it("bands cases for the choropleth", () => {
    expect(bandFor(0, 17)).toBe(0);
    expect(bandFor(1, 17)).toBe(1);
    expect(bandFor(17, 17)).toBe(5);
    expect(bandFor(9, 17)).toBe(3);
    expect(bandFor(4, 0)).toBe(0);
  });

  it("lists the outbreak cells newest week first", () => {
    const out = outbreakCells([
      cell({ outbreak: true, week_start: "2026-09-07" }),
      cell({ outbreak: false }),
      cell({ outbreak: true, week_start: "2026-09-14" }),
    ]);
    expect(out.map((c) => c.week_start)).toEqual(["2026-09-14", "2026-09-07"]);
  });
});

// ---- DX-011 accuracy trend (C62) -------------------------------------------------------------
function run(over: Partial<EvaluationRun>): EvaluationRun {
  return {
    id: "eval-1",
    status: "ok",
    manifest: "gs://corpus/eval/manifest.csv",
    started_at: "2026-09-18T01:00:00Z",
    finished_at: "2026-09-18T01:15:00Z",
    encoder: "clip-vit-b32@1",
    llm: "gemini-1.5-flash",
    corpus_version: 41,
    cases: 100,
    top1_accuracy: 0.85,
    corpus_answer_share: 0.6,
    escalation_rate: 0.2,
    hallucinated_out_of_scope: 0,
    previous_run_id: null,
    top1_delta_points: null,
    alerted: false,
    crops: [],
    error: null,
    ...over,
  };
}

describe("evaluation accuracy trend", () => {
  const older = run({
    id: "a",
    started_at: "2026-09-16T01:00:00Z",
    crops: [
      { crop_code: "paddy", cases: 60, correct: 51, top1_accuracy: 0.85 },
      { crop_code: "chilli", cases: 10, correct: 7, top1_accuracy: 0.7 },
    ],
  });
  const newer = run({
    id: "b",
    started_at: "2026-09-18T01:00:00Z",
    top1_accuracy: 0.9,
    crops: [{ crop_code: "paddy", cases: 70, correct: 63, top1_accuracy: 0.9 }],
  });

  it("orders crops by how many cases they were tested on", () => {
    expect(trendCrops([newer, older])).toEqual(["paddy", "chilli"]);
    expect(trendCrops([newer, older], 1)).toEqual(["paddy"]);
  });

  it("puts the oldest run first and leaves a crop absent from a run null", () => {
    const points = accuracyTrend([newer, older], ["paddy", "chilli"]);
    expect(points.map((p) => p.id)).toEqual(["a", "b"]);
    expect(points[0]).toMatchObject({ paddy: 0.85, chilli: 0.7, overall: 0.85 });
    expect(points[1]).toMatchObject({ paddy: 0.9, chilli: null, overall: 0.9 });
  });

  it("has no crops and no points without runs", () => {
    expect(trendCrops([])).toEqual([]);
    expect(accuracyTrend([], [])).toEqual([]);
  });
});
