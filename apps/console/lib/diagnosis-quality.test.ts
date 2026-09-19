import { describe, expect, it } from "vitest";
import { ageBucket, summariseQuality } from "./diagnosis-quality";

const H = 3_600_000;
const NOW = Date.parse("2026-09-19T12:00:00Z");
const at = (hoursAgo: number) => new Date(NOW - hoursAgo * H).toISOString();

type Row = Parameters<typeof summariseQuality>[0][number];
const row = (r: Partial<Row>): Row => ({
  status: "answered",
  source: "corpus",
  flagged: false,
  created_at: at(48),
  reviewed_at: null,
  crop_id: "crop-paddy",
  out_of_scope_reason: null,
  final_problem_id: "p1",
  ...r,
});

describe("C62 basic quality summary (AN-007 subset)", () => {
  it("counts by source, corpus share, escalation and review SLA", () => {
    const s = summariseQuality(
      [
        row({}),
        row({}),
        row({ status: "provisional", source: "llm", final_problem_id: null }),
        row({ status: "corrected", source: "agronomist", reviewed_at: at(40) }),
        row({ status: "confirmed", source: "agronomist", reviewed_at: at(10) }),
        row({
          status: "out_of_scope",
          source: null,
          out_of_scope_reason: "not_a_plant",
          final_problem_id: null,
        }),
        row({ status: "queued", source: null }),
      ],
      [],
      NOW,
    );
    expect(s.total).toBe(6);
    expect(s.bySource).toEqual({ corpus: 2, llm: 1, agronomist: 2, none: 1 });
    expect(s.corpusShare).toBeCloseTo(2 / 5);
    expect(s.escalationRate).toBeCloseTo(4 / 6);
    expect(s.reviewed).toBe(2);
    expect(s.reviewedIn24h).toBeCloseTo(1 / 2);
  });

  it("buckets the queue by age and ranks unknowns by crop and reason", () => {
    const s = summariseQuality(
      [
        row({
          status: "out_of_scope",
          source: null,
          out_of_scope_reason: "no_match",
          crop_id: "c1",
        }),
        row({
          status: "out_of_scope",
          source: null,
          out_of_scope_reason: "no_match",
          crop_id: "c1",
        }),
        row({ status: "provisional", source: "llm", final_problem_id: null, crop_id: "c2" }),
      ],
      [
        { created_at: at(1) },
        { created_at: at(7) },
        { created_at: at(19) },
        { created_at: at(30) },
        { created_at: at(2) },
      ],
      NOW,
    );
    expect(s.queueAges).toEqual({ lt6: 2, h6to18: 1, h18to24: 1, gt24: 1 });
    expect(s.topUnknowns).toEqual([
      { cropId: "c1", reason: "no_match", count: 2 },
      { cropId: "c2", reason: "llm_unknown", count: 1 },
    ]);
  });

  it("reports no rates on an empty period", () => {
    const s = summariseQuality([], [], NOW);
    expect(s.corpusShare).toBeNull();
    expect(s.escalationRate).toBeNull();
    expect(s.reviewedIn24h).toBeNull();
    expect(ageBucket(18)).toBe("h18to24");
    expect(ageBucket(24)).toBe("gt24");
  });
});
