/**
 * In-memory AN-006 crop health, AN-007 diagnosis quality / DX-011 evaluations and DX-012 model
 * releases for the mock API, so the crop-health map, C62 and the model-release view run offline.
 * Mirrors docs/prs/M7-farmer-p1-api.md. AN-014: crop health is district level only — the cells
 * carry a district centroid and never a farm location or a farmer id. Holds no real data.
 */
import type { MockActor, MockResult } from "./catalog";
import { mockStepUpOk, recordAudit } from "./admin";
import { MOCK_STORES } from "./analytics";

type Json = Record<string, unknown>;

const QUALITY_ROLES = ["owner", "director", "tenant_admin", "auditor", "agronomist"];
const RELEASE_READ = ["agronomist", "owner", "director", "tenant_admin"];
const RELEASE_DECIDE = ["agronomist", "owner"];

function problem(status: number, code: string, detail?: string, extra?: Json): MockResult {
  return {
    status,
    json: {
      type: `https://farmerapp.dev/problems/${code}`,
      title: code,
      status,
      code,
      detail,
      ...extra,
    },
    headers: { "content-type": "application/problem+json" },
  };
}
const ok = (json: unknown, status = 200): MockResult => ({ status, json });

function rnd(seed: string): number {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 100000) / 100000;
}

const D = 86_400_000;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();

// ---- AN-006 crop health -------------------------------------------------------------------

const CROPS = [
  { id: "crop-cotton", code: "cotton", names: { en: "Cotton", te: "పత్తి" } },
  { id: "crop-paddy", code: "paddy", names: { en: "Paddy", te: "వరి" } },
  { id: "crop-chilli", code: "chilli", names: { en: "Chilli", te: "మిరప" } },
];

const PROBLEMS = [
  {
    id: "prob-pbw",
    code: "pink_bollworm",
    type: "pest",
    crop: "crop-cotton",
    names: { en: "Pink bollworm", te: "గులాబీ కాయతొలుచు పురుగు" },
  },
  {
    id: "prob-blast",
    code: "rice_blast",
    type: "disease",
    crop: "crop-paddy",
    names: { en: "Rice blast", te: "వరి అగ్గి తెగులు" },
  },
  {
    id: "prob-thrips",
    code: "thrips",
    type: "pest",
    crop: "crop-chilli",
    names: { en: "Thrips", te: "తామర పురుగు" },
  },
];

/** ISO week of a date (Monday-based), as the API reports it. */
function isoWeek(date: Date): { year: number; week: number; start: string } {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - day);
  const start = d.toISOString().slice(0, 10);
  const thursday = new Date(d);
  thursday.setUTCDate(thursday.getUTCDate() + 3);
  const firstThursday = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 4));
  const firstDay = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - firstDay + 3);
  const week = 1 + Math.round((thursday.getTime() - firstThursday.getTime()) / (7 * D));
  return { year: thursday.getUTCFullYear(), week, start };
}

/** District x crop x problem x week cells for the last `weeks` ISO weeks. */
function cropHealth(weeks: number, district: string | null, cropId: string | null): Json[] {
  const items: Json[] = [];
  const districts = MOCK_STORES.slice(0, 10);
  for (let w = 0; w < weeks; w++) {
    const { year, week, start } = isoWeek(new Date(Date.now() - w * 7 * D));
    for (const store of districts) {
      if (district && store.district.toLowerCase() !== district.toLowerCase()) continue;
      for (const p of PROBLEMS) {
        if (cropId && p.crop !== cropId) continue;
        const crop = CROPS.find((c) => c.id === p.crop)!;
        const seed = `${store.district}:${p.code}:${year}-${week}`;
        const base = Math.floor(rnd(`${seed}:base`) * 7);
        // One deliberate outbreak: Warangal cotton in the most recent week.
        const spike = w === 0 && store.district === "Warangal" && p.code === "pink_bollworm";
        const cases = spike ? 14 : base;
        if (cases === 0) continue;
        const prior = spike ? 3.5 : Math.max(0.5, base * (0.7 + rnd(`${seed}:prior`) * 0.5));
        const outbreak = cases >= 3 && cases >= 2 * prior;
        items.push({
          district: store.district,
          crop_id: crop.id,
          crop_code: crop.code,
          crop_names: crop.names,
          problem_id: p.id,
          problem_code: p.code,
          problem_type: p.type,
          problem_names: p.names,
          iso_year: year,
          iso_week: week,
          week_start: start,
          confirmed_cases: cases,
          farmers_affected: Math.max(1, Math.round(cases * 0.8)),
          prior_mean: Math.round(prior * 10) / 10,
          outbreak,
          alert_id: outbreak ? `alert-${store.code.toLowerCase()}-${p.code}-${week}` : null,
          latitude: store.lat,
          longitude: store.lon,
        });
      }
    }
  }
  return items;
}

// ---- AN-007 quality + DX-011 evaluations ----------------------------------------------------

interface Evaluation {
  id: string;
  model_name: string;
  model_version: string;
  ran_at: string;
  status: string;
  cases: number;
  top1_accuracy: number | null;
  corpus_answer_share: number | null;
  escalation_rate: number | null;
  hallucinated_out_of_scope: number | null;
  top1_delta_points: number | null;
  alerted: boolean;
  per_crop: Json[];
  per_problem: Json[];
  error: string | null;
}

function evaluation(n: number, version: string, accuracy: number, delta: number): Evaluation {
  return {
    id: `eval-${String(n).padStart(4, "0")}`,
    model_name: "farmerapp-ondevice",
    model_version: version,
    ran_at: iso(-n * D),
    status: "completed",
    cases: 420,
    top1_accuracy: accuracy,
    corpus_answer_share: 0.62,
    escalation_rate: 0.18,
    hallucinated_out_of_scope: 3,
    top1_delta_points: delta,
    alerted: delta < -5,
    per_crop: CROPS.map((c, i) => ({
      crop_id: c.id,
      crop_code: c.code,
      cases: 140 - i * 20,
      top1_accuracy: Math.round((accuracy + (i - 1) * 0.04) * 1000) / 1000,
    })),
    per_problem: PROBLEMS.map((p, i) => ({
      problem_code: p.code,
      cases: 90 - i * 15,
      top1_accuracy: Math.round((accuracy - i * 0.03) * 1000) / 1000,
    })),
    error: null,
  };
}

function quality(days: number): Json {
  const requests = Math.round(days * 41);
  const corpus = Math.round(requests * 0.62);
  const escalated = Math.round(requests * 0.18);
  return {
    days,
    requests,
    answered_by_corpus: corpus,
    corpus_share: corpus / requests,
    escalated,
    escalation_rate: escalated / requests,
    llm_share: 0.29,
    by_source: {
      corpus,
      llm: Math.round(requests * 0.29),
      agronomist: Math.round(requests * 0.06),
      none: requests - corpus - Math.round(requests * 0.29) - Math.round(requests * 0.06),
    },
    by_status: {
      confirmed: Math.round(requests * 0.55),
      provisional: Math.round(requests * 0.22),
      corrected: Math.round(requests * 0.09),
      out_of_scope: Math.round(requests * 0.08),
      queued: Math.round(requests * 0.06),
    },
    review: {
      sla_hours: 24,
      reviewed: 168,
      reviewed_within_sla: 151,
      sla_rate: 151 / 168,
      avg_review_hours: 9.4,
      median_review_hours: 7.1,
      open_queue: 5,
      open_overdue: 2,
    },
    top_unknowns: [
      { crop_id: "crop-tomato", crop_code: "tomato", reason: "unsupported_crop", cases: 17 },
      { crop_id: "crop-cotton", crop_code: "cotton", reason: "unreadable_image", cases: 11 },
      { crop_id: null, crop_code: null, reason: "not_a_plant", cases: 9 },
      { crop_id: "crop-paddy", crop_code: "paddy", reason: "llm_unknown", cases: 6 },
      { crop_id: "crop-chilli", crop_code: "chilli", reason: "no_match", cases: 4 },
    ],
    latest_evaluation: db.evaluations[0],
  };
}

// ---- DX-012 releases -------------------------------------------------------------------------

interface Release {
  id: string;
  model_name: string;
  model_version: string;
  status: string;
  sha256: string;
  size_bytes: number;
  labels: string[];
  notes: string | null;
  created_at: string;
  approved_at: string | null;
  decided_by: string | null;
  decision_note: string | null;
  evaluation: Evaluation | null;
  top1_delta_points: number | null;
}

interface Db {
  evaluations: Evaluation[];
  releases: Release[];
}

function seed(): Db {
  const evals = [
    evaluation(1, "2026.09.2", 0.871, 2.4),
    evaluation(8, "2026.09.1", 0.847, 0.9),
    evaluation(15, "2026.08.4", 0.838, -1.2),
  ];
  const labels = ["healthy", "pink_bollworm", "rice_blast", "thrips", "nutrient_deficiency"];
  const releases: Release[] = [
    {
      id: "rel-0003",
      model_name: "farmerapp-ondevice",
      model_version: "2026.09.2",
      status: "candidate",
      sha256: "9f2c1b6ad4e7c0a3b5d8e2f14c7a9b0d3e6f815a2c4b7d9e0f1a3c5b7d9e0f12",
      size_bytes: 12_845_312,
      labels,
      notes: "Monthly fine-tune on September field images.",
      created_at: iso(-1 * D),
      approved_at: null,
      decided_by: null,
      decision_note: null,
      evaluation: evals[0]!,
      top1_delta_points: 2.4,
    },
    {
      id: "rel-0002",
      model_name: "farmerapp-ondevice",
      model_version: "2026.09.1",
      status: "approved",
      sha256: "3a1d5e9c7b2f4086d1c3e5a7b9d0f2468ace13579bdf02468ace13579bdf0246",
      size_bytes: 12_744_064,
      labels,
      notes: null,
      created_at: iso(-8 * D),
      approved_at: iso(-7 * D),
      decided_by: "u-agronomist",
      decision_note: "Accuracy up on cotton and paddy.",
      evaluation: evals[1]!,
      top1_delta_points: 0.9,
    },
    {
      id: "rel-0001",
      model_name: "farmerapp-ondevice",
      model_version: "2026.08.4",
      status: "rejected",
      sha256: "77bb11cc22dd33ee44ff5500aa66bb77cc88dd99ee00ff11223344556677889a",
      size_bytes: 12_701_120,
      labels,
      notes: null,
      created_at: iso(-15 * D),
      approved_at: null,
      decided_by: "u-agronomist",
      decision_note: "Chilli accuracy regressed.",
      evaluation: evals[2]!,
      top1_delta_points: -1.2,
    },
  ];
  return { evaluations: evals, releases };
}

let db: Db = seed();

export function resetMockMlops(): void {
  db = seed();
}

/** Handles `/analytics/crop-health`, `/diagnoses/quality|evaluations` and `/models/*`. */
export function handleMlops(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor | null,
  headers: Headers,
): MockResult | null {
  const [a, b, c, d] = path;
  const isCropHealth = a === "analytics" && b === "crop-health";
  const isQuality = a === "diagnoses" && (b === "quality" || b === "evaluations");
  const isModels = a === "models";
  if (!isCropHealth && !isQuality && !isModels) return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  const role = actor.role;

  if (isCropHealth) {
    if (method !== "GET") return problem(405, "method_not_allowed", "Read-only.");
    if (!QUALITY_ROLES.includes(role))
      return problem(403, "forbidden", "Your role cannot read crop health.");
    const weeks = Math.min(26, Math.max(1, Number(query.get("weeks") ?? 8)));
    return ok({ weeks, items: cropHealth(weeks, query.get("district"), query.get("crop_id")) });
  }

  if (isQuality) {
    if (method !== "GET") return problem(405, "method_not_allowed", "Read-only.");
    if (!QUALITY_ROLES.includes(role))
      return problem(403, "forbidden", "Your role cannot read diagnosis quality.");
    if (b === "quality")
      return ok(quality(Math.min(180, Math.max(1, Number(query.get("days") ?? 30)))));
    if (c) {
      const found = db.evaluations.find((e) => e.id === c);
      return found ? ok(found) : problem(404, "not_found", "Evaluation not found.");
    }
    return ok({ items: db.evaluations });
  }

  // /models/on-device/current and /models/releases[/{id}[/decision]]
  if (b === "on-device" && c === "current") {
    const approved = db.releases.find((r) => r.status === "approved");
    if (!approved) return problem(404, "no_approved_model", "No approved release yet.");
    return ok({
      release_id: approved.id,
      model_name: approved.model_name,
      model_version: approved.model_version,
      sha256: approved.sha256,
      size_bytes: approved.size_bytes,
      approved_at: approved.approved_at,
      labels: approved.labels,
    });
  }
  if (b !== "releases") return problem(404, "not_found", "Unknown models route.");
  if (!RELEASE_READ.includes(role))
    return problem(403, "forbidden", "Your role cannot read model releases.");
  if (method === "GET" && !c) {
    const status = query.get("status");
    return ok({ items: db.releases.filter((r) => !status || r.status === status) });
  }
  const release = db.releases.find((r) => r.id === c);
  if (!release) return problem(404, "not_found", "Release not found.");
  if (method === "GET") return ok(release);
  if (method === "POST" && d === "decision") {
    if (!RELEASE_DECIDE.includes(role))
      return problem(403, "forbidden", "Agronomists and owners decide releases.");
    if (!mockStepUpOk(headers, actor))
      return problem(401, "step_up_required", "This action needs a fresh one-time code.", {
        step_up_url: "/v1/auth/step-up/send",
      });
    const decision = String(body.decision ?? "");
    if (!["approve", "reject", "retire"].includes(decision))
      return problem(422, "validation_error", "Unknown decision.");
    if (decision === "approve") {
      if (release.status !== "candidate")
        return problem(409, "invalid_transition", "Only a candidate can be approved.");
      if (!release.evaluation)
        return problem(409, "evaluation_missing", "This candidate has no evaluation run.");
      for (const r of db.releases) if (r.status === "approved") r.status = "retired";
      release.status = "approved";
      release.approved_at = new Date().toISOString();
    } else if (decision === "reject") {
      if (release.status !== "candidate")
        return problem(409, "invalid_transition", "Only a candidate can be rejected.");
      release.status = "rejected";
    } else {
      if (release.status !== "approved")
        return problem(409, "invalid_transition", "Only the approved release can be retired.");
      release.status = "retired";
    }
    release.decided_by = actor.id;
    release.decision_note = (body.note as string) ?? null;
    recordAudit(actor, `model_release.${decision}`, "model_release", release.id, null, {
      status: release.status,
    });
    return ok(release);
  }
  return problem(405, "method_not_allowed", "Unsupported models call.");
}
