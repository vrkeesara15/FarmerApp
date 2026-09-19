/**
 * In-memory crop doctor data for the mock API (WC-006, WC-007, DX-005, DX-006) so C60-C62 run
 * without apps/api. Mirrors `/v1/diagnoses*` and `/v1/corpus/*` of apps/api/openapi.yaml: the
 * review queue (oldest first, `age_hours`, `overdue` > 18 h, counts), the review action
 * (confirm / correct / not_diagnosable, rebuilt result, `add_to_corpus` as reviewed images,
 * append-only reviews; 409 `diagnosis_not_reviewable`, 422 `review_invalid`), corpus problems /
 * images with the draft -> reviewed -> approved -> retired workflow (409 `invalid_transition`,
 * `corpus_entry_locked`, `corpus_problem_exists`, `corpus_image_exists`), approvals bumping the
 * corpus version once, and `/v1/uploads` (chunked, purpose `corpus`). Crop and pest ids are the
 * catalogue mock's (lib/mock/catalog.ts). Holds no real data: farmers are ids only.
 */
import type { MockActor, MockResult } from "./catalog";

type Json = Record<string, unknown>;
type CorpusStatus = "draft" | "reviewed" | "approved" | "retired";

const QUEUE_READ = ["agronomist", "owner"];
const DIAG_READ = [
  "agronomist",
  "auditor",
  "cluster_head",
  "director",
  "farmer",
  "field_officer",
  "owner",
  "store_manager",
  "tenant_admin",
];
const CORPUS_READ = ["agronomist", "director", "owner"];
const AGRONOMIST = ["agronomist"];
/** apps/api UPLOAD_ROLES plus the agronomist for corpus images (see docs/prs/M6-console-agronomist.md). */
const UPLOAD = [
  "cluster_head",
  "farmer",
  "field_officer",
  "store_manager",
  "tenant_admin",
  "agronomist",
];
const TRANSITIONS: Record<CorpusStatus, CorpusStatus[]> = {
  draft: ["reviewed", "retired"],
  reviewed: ["approved", "draft", "retired"],
  approved: ["retired"],
  retired: [],
};
const ALERT_HOURS = 18;
const H = 3_600_000;
const ENCODER = { name: "siglip-base-patch16-224", version: "2024-01" };
const MODELS = {
  encoder: "siglip-base-patch16-224@2024-01",
  on_device: "ondevice-v1.0",
};
const LLM_MODEL = "claude-opus-5";

const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
const uid = (prefix: string, n: number) =>
  `${prefix}-0000-4000-8000-${String(n).padStart(12, "0")}`;

/** Inline SVG "field photo" so images render offline (the API returns 15-min signed URLs). */
function leafPhoto(label: string, hue: number, spots: number): string {
  const dots = Array.from({ length: spots }, (_, i) => {
    const x = 90 + ((i * 53) % 150);
    const y = 70 + ((i * 37) % 100);
    return `<ellipse cx="${x}" cy="${y}" rx="9" ry="5" fill="hsl(${(hue + 190) % 360},40%,35%)" opacity="0.8"/>`;
  }).join("");
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240"><rect width="320" height="240" fill="hsl(${hue},30%,82%)"/><path d="M40 200 C 80 40, 240 20, 290 40 C 260 140, 160 220, 40 200 Z" fill="hsl(${hue},50%,38%)"/><path d="M40 200 L 290 40" stroke="hsl(${hue},40%,70%)" stroke-width="3"/>${dots}<text x="12" y="228" font-family="sans-serif" font-size="14" fill="#1b1b1b">${label}</text></svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

// ---- corpus ------------------------------------------------------------------------------
interface Problem {
  id: string;
  pest_or_disease_id: string;
  pest_code: string;
  crop_id: string;
  problem_type: string;
  names: Record<string, string>;
  symptoms: Record<string, string[]>;
  cultural_practices: Record<string, string[]>;
  status: CorpusStatus;
  source: string;
  labelled_by: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  approved_by: string | null;
  approved_at: string | null;
  approved_in_version: number | null;
  retired_at: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  version: number;
}

interface Image {
  id: string;
  problem_id: string;
  crop_id: string;
  blob_uri: string;
  sha256: string;
  encoder_name: string;
  encoder_version: string;
  stage: string | null;
  part: string | null;
  severity: string | null;
  region: string | null;
  season: string | null;
  source: string;
  status: CorpusStatus;
  labelled_by: string | null;
  approved_by: string | null;
  approved_at: string | null;
  approved_in_version: number | null;
  from_diagnosis_id: string | null;
  created_at: string;
  version: number;
  signed_url: string;
}

interface Version {
  id: string;
  version: number;
  approved_by: string | null;
  note: string | null;
  changes: { problems: string[]; images: string[]; retired: string[] };
  created_at: string;
}

interface Diag {
  id: string;
  subject: string;
  farmer_id: string;
  crop_plot_id: string | null;
  requested_by: string | null;
  crop_id: string | null;
  crop_detected_on_device: Json | null;
  district: string | null;
  season: string | null;
  crop_stage: string | null;
  status: string;
  source: string | null;
  confidence: string | null;
  provisional: boolean;
  can_buy: boolean;
  cta: string | null;
  message_key: string | null;
  result: Json | null;
  final_problem_id: string | null;
  out_of_scope_reason: string | null;
  flagged: boolean;
  ask_expert: boolean;
  model_versions: Json;
  corpus_version: number | null;
  images: Json[];
  captured_at: string | null;
  answered_at: string | null;
  reviewed_at: string | null;
  reviewed_by: string | null;
  created_at: string;
  updated_at: string;
  version: number;
  llm_used: boolean;
  scores: Json | null;
  reviews: Json[];
}

interface Upload {
  upload_id: string;
  sha256: string;
  size_bytes: number;
  content_type: string;
  chunk_size: number;
  chunks: Map<number, Uint8Array>;
  blob_uri: string | null;
  expires_at: string;
}

interface Db {
  problems: Problem[];
  images: Image[];
  versions: Version[];
  diagnoses: Diag[];
  uploads: Map<string, Upload>;
  /** blob_uri -> data URL of the uploaded bytes (what a signed URL would serve). */
  blobs: Map<string, { dataUrl: string; sha256: string }>;
  seq: number;
}

const P = {
  paddyBlast: uid("c0a1b2c3", 1),
  paddyZinc: uid("c0a1b2c3", 2),
  paddyAphids: uid("c0a1b2c3", 3),
  paddyBphOld: uid("c0a1b2c3", 4),
  cottonPbw: uid("c0a1b2c3", 5),
  cottonAphids: uid("c0a1b2c3", 6),
  chilliThrips: uid("c0a1b2c3", 7),
  chilliZinc: uid("c0a1b2c3", 8),
};

const NAMES = {
  blast: {
    en: "Rice blast",
    te: "అగ్గి తెగులు",
    kn: "ಬೆಂಕಿ ರೋಗ",
    hi: "झोंका रोग (ब्लास्ट)",
    mr: "करपा रोग",
  },
  zinc: {
    en: "Zinc deficiency (khaira)",
    te: "జింక్ లోపం",
    kn: "ಸತುವಿನ ಕೊರತೆ",
    hi: "जस्ते की कमी (खैरा)",
    mr: "जस्ताची कमतरता",
  },
  aphids: { en: "Aphids", te: "పేనుబంక", kn: "ಸಸ್ಯ ಹೇನು", hi: "माहू", mr: "मावा" },
  bph: {
    en: "Brown planthopper",
    te: "సుడిదోమ",
    kn: "ಕಂದು ಜಿಗಿಹುಳು",
    hi: "भूरा फुदका",
    mr: "तपकिरी तुडतुडे",
  },
  pbw: {
    en: "Pink bollworm",
    te: "గులాబీ రంగు కాయతొలుచు పురుగు",
    kn: "ಗುಲಾಬಿ ಕಾಯಿಕೊರಕ",
    hi: "गुलाबी सुंडी",
    mr: "शेंदरी बोंडअळी",
  },
  thrips: {
    en: "Chilli thrips",
    te: "తామర పురుగు",
    kn: "ಥ್ರಿಪ್ಸ್ ನುಸಿ",
    hi: "थ्रिप्स",
    mr: "फुलकिडे",
  },
};

const SYMPTOMS = {
  blast: {
    en: [
      "Spindle-shaped spots with grey centres on leaves",
      "Brown margins around the spots",
      "Neck of the panicle turns black and breaks",
    ],
    te: ["ఆకులపై బూడిద రంగు మధ్యభాగంతో కదురు ఆకారపు మచ్చలు", "మచ్చల చుట్టూ గోధుమ రంగు అంచులు"],
    hi: ["पत्तियों पर धूसर केंद्र वाले तर्कु आकार के धब्बे", "धब्बों के चारों ओर भूरा किनारा"],
  },
  zinc: {
    en: ["Rusty brown spots on older leaves", "Stunted plants with short internodes"],
    te: ["ముదురు ఆకులపై తుప్పు రంగు మచ్చలు", "మొక్కలు పొట్టిగా ఉంటాయి"],
  },
  aphids: { en: ["Clusters of small soft insects under leaves", "Sticky honeydew on leaves"] },
  bph: { en: ["Hopper burn: circular patches of dried plants", "Insects at the base of tillers"] },
  pbw: {
    en: ["Rosette flowers", "Exit holes on green bolls", "Stained lint inside bolls"],
    te: ["గులాబీ పువ్వుల వంటి ముడుచుకున్న పూలు", "కాయలపై రంధ్రాలు"],
  },
  thrips: { en: ["Upward curling of leaves", "Silvery streaks on leaf surface"] },
};

function seedProblem(
  id: string,
  pest: string,
  crop: string,
  type: string,
  names: Record<string, string>,
  symptoms: Record<string, string[]>,
  status: CorpusStatus,
  source: string,
  approvedIn: number | null,
): Problem {
  const created = iso(-40 * 24 * H);
  return {
    id,
    pest_or_disease_id: `pest-${pest}`,
    pest_code: pest,
    crop_id: `crop-${crop}`,
    problem_type: type,
    names,
    symptoms,
    cultural_practices: {
      en: ["Remove and destroy affected plant parts", "Avoid excess nitrogen"],
    },
    status,
    source,
    labelled_by: "u-agronomist",
    reviewed_by: status === "draft" ? null : "u-agronomist",
    reviewed_at: status === "draft" ? null : iso(-35 * 24 * H),
    approved_by: approvedIn ? "u-agronomist" : null,
    approved_at: approvedIn ? iso(-(30 - approvedIn) * 24 * H) : null,
    approved_in_version: approvedIn,
    retired_at: status === "retired" ? iso(-10 * 24 * H) : null,
    notes: source === "public" ? "Bootstrap from a licensed public dataset (source=public)." : null,
    created_at: created,
    updated_at: created,
    version: 1,
  };
}

const HUES: Record<string, number> = {
  "crop-paddy": 95,
  "crop-cotton": 120,
  "crop-chilli": 105,
  "crop-tomato": 110,
};

function seed(): Db {
  const problems: Problem[] = [
    seedProblem(
      P.paddyBlast,
      "paddy_blast",
      "paddy",
      "disease",
      NAMES.blast,
      SYMPTOMS.blast,
      "approved",
      "internal",
      3,
    ),
    seedProblem(
      P.paddyZinc,
      "zinc_deficiency",
      "paddy",
      "nutrient",
      NAMES.zinc,
      SYMPTOMS.zinc,
      "approved",
      "public",
      1,
    ),
    seedProblem(
      P.paddyAphids,
      "aphids",
      "paddy",
      "pest",
      NAMES.aphids,
      SYMPTOMS.aphids,
      "reviewed",
      "internal",
      null,
    ),
    seedProblem(
      P.paddyBphOld,
      "paddy_bph",
      "paddy",
      "pest",
      NAMES.bph,
      SYMPTOMS.bph,
      "retired",
      "public",
      1,
    ),
    seedProblem(
      P.cottonPbw,
      "cotton_pbw",
      "cotton",
      "pest",
      NAMES.pbw,
      SYMPTOMS.pbw,
      "approved",
      "internal",
      5,
    ),
    seedProblem(
      P.cottonAphids,
      "aphids",
      "cotton",
      "pest",
      NAMES.aphids,
      SYMPTOMS.aphids,
      "approved",
      "public",
      1,
    ),
    seedProblem(
      P.chilliThrips,
      "chilli_thrips",
      "chilli",
      "pest",
      NAMES.thrips,
      SYMPTOMS.thrips,
      "approved",
      "internal",
      7,
    ),
    seedProblem(
      P.chilliZinc,
      "zinc_deficiency",
      "chilli",
      "nutrient",
      NAMES.zinc,
      SYMPTOMS.zinc,
      "draft",
      "internal",
      null,
    ),
  ];
  const images: Image[] = [];
  let n = 0;
  const parts = ["leaf", "leaf", "stem", "whole"];
  const regions = ["Warangal", "Karimnagar", "Raichur", "Nanded"];
  for (const p of problems) {
    const count = p.status === "approved" ? 4 : p.status === "retired" ? 2 : 2;
    for (let i = 0; i < count; i++) {
      n += 1;
      const status: CorpusStatus =
        p.status === "approved"
          ? i < 3
            ? "approved"
            : "reviewed"
          : p.status === "retired"
            ? "retired"
            : "draft";
      const label = `${p.names.en} ${i + 1}`;
      images.push({
        id: uid("c1a1b2c3", n),
        problem_id: p.id,
        crop_id: p.crop_id,
        blob_uri: `gs://farmerapp-dev-media/t1/corpus/${p.pest_code}-${i + 1}.jpg`,
        sha256: n.toString(16).padStart(64, "0"),
        encoder_name: ENCODER.name,
        encoder_version: ENCODER.version,
        stage: i % 2 ? "flowering" : "vegetative",
        part: parts[i % parts.length] ?? "leaf",
        severity: (["low", "medium", "high"] as const)[i % 3] ?? "medium",
        region: regions[i % regions.length] ?? null,
        season: "kharif",
        source: p.source,
        status,
        labelled_by: "u-agronomist",
        approved_by: status === "approved" ? "u-agronomist" : null,
        approved_at: status === "approved" ? p.approved_at : null,
        approved_in_version: status === "approved" ? p.approved_in_version : null,
        from_diagnosis_id: null,
        created_at: iso(-(38 - i) * 24 * H),
        version: 1,
        signed_url: leafPhoto(label, HUES[p.crop_id] ?? 100, 3 + i * 2),
      });
    }
  }
  const versions: Version[] = [1, 2, 3, 4, 5, 6, 7].map((v) => ({
    id: uid("c2a1b2c3", v),
    version: v,
    approved_by: "u-agronomist",
    note:
      v === 1
        ? "Public bootstrap corpus (source=public)"
        : v === 3
          ? "Rice blast field images, Warangal kharif"
          : null,
    changes: {
      problems:
        v === 1
          ? [P.paddyZinc, P.paddyBphOld, P.cottonAphids]
          : v === 3
            ? [P.paddyBlast]
            : v === 5
              ? [P.cottonPbw]
              : v === 7
                ? [P.chilliThrips]
                : [],
      images: v === 2 || v === 4 || v === 6 ? [uid("c1a1b2c3", v)] : [],
      retired: [],
    },
    created_at: iso(-(31 - v * 3) * 24 * H),
  }));
  return {
    problems,
    images,
    versions,
    diagnoses: seedDiagnoses(problems),
    uploads: new Map(),
    blobs: new Map(),
    seq: 100,
  };
}

// ---- diagnoses ---------------------------------------------------------------------------
const FARMERS = [1, 2, 3, 4, 5, 6, 7, 8].map((i) => uid("fa0e0000", i));
const OFFICER = "u-field_officer";

function photos(id: number, cropId: string, count: number): Json[] {
  return Array.from({ length: count }, (_, i) => ({
    blob_uri: `gs://farmerapp-dev-media/t1/diagnosis/${id}-${i + 1}.jpg`,
    sha256: (id * 10 + i).toString(16).padStart(64, "a"),
    quality: { passed: true, blur_score: 180 + i * 12, brightness: 0.52, plant_present: true },
    signed_url: leafPhoto(`Photo ${i + 1}`, HUES[cropId] ?? 100, 6 + id + i),
  }));
}

function problemJson(p: Problem): Json {
  return {
    id: p.id,
    pest_or_disease_id: p.pest_or_disease_id,
    code: p.pest_code,
    type: p.problem_type,
    crop_id: p.crop_id,
    names: p.names,
    symptoms: p.symptoms,
  };
}

function resultFor(
  problem: Problem | null,
  opts: {
    confidence: string;
    provisional: boolean;
    canBuy: boolean;
    messageKey: string;
    visible?: string[];
    outOfScope?: string | null;
  },
): Json {
  return {
    problem: problem ? problemJson(problem) : null,
    confidence: opts.confidence,
    provisional: opts.provisional,
    can_buy: opts.canBuy,
    cta: opts.canBuy ? "buy" : opts.outOfScope ? "ask_expert" : "talk_to_field_officer",
    message_key: opts.messageKey,
    out_of_scope_reason: opts.outOfScope ?? null,
    visible_symptoms: opts.visible ?? [],
    treatments: problem
      ? { organic: [], chemical: [], cultural: problem.cultural_practices, store: null }
      : null,
  };
}

interface DiagSeed {
  n: number;
  crop: string;
  ageH: number;
  status: string;
  source: string | null;
  confidence: string | null;
  problem: string | null;
  llm: Json | null;
  candidates: Array<[string, number, number]>;
  oos?: string | null;
  flagged?: boolean;
  askExpert?: boolean;
  district: string;
  season: string;
  stage: string;
  reviewedAfterH?: number;
}

function diag(s: DiagSeed, problems: Problem[]): Diag {
  const cropId = `crop-${s.crop}`;
  const created = iso(-s.ageH * H);
  const answered = iso(-s.ageH * H + 4000);
  const provisional = s.status === "provisional";
  const oos = s.status === "out_of_scope";
  const canBuy = ["answered", "confirmed", "corrected"].includes(s.status);
  const proposal = s.candidates[0]?.[0] ?? null;
  const votes: Record<string, number> = {};
  for (const [pid, , v] of s.candidates) votes[pid] = v;
  const top1 = s.candidates[0]?.[1] ?? 0.71;
  const problem = s.problem ? (problems.find((p) => p.id === s.problem) ?? null) : null;
  const reviewed = s.reviewedAfterH !== undefined;
  return {
    id: uid("d1a90000", s.n),
    subject: s.n % 2 ? "officer" : "farmer",
    farmer_id: FARMERS[s.n % FARMERS.length]!,
    crop_plot_id: null,
    requested_by: s.n % 2 ? OFFICER : null,
    crop_id: cropId,
    crop_detected_on_device: { code: s.crop, confidence: 0.91 },
    district: s.district,
    season: s.season,
    crop_stage: s.stage,
    status: s.status,
    source: s.source,
    confidence: s.confidence,
    provisional,
    can_buy: canBuy,
    cta: canBuy ? "buy" : oos ? "ask_expert" : "talk_to_field_officer",
    message_key: oos
      ? `diagnosis.out_of_scope.${s.oos ?? "no_match"}`
      : `diagnosis.result.${provisional ? "provisional" : s.status}`,
    result: oos
      ? null
      : resultFor(problem, {
          confidence: s.confidence ?? "low",
          provisional,
          canBuy,
          messageKey: `diagnosis.result.${provisional ? "provisional" : s.status}`,
          visible: s.llm ? ["grey spindle-shaped lesions", "brown margins"] : [],
        }),
    final_problem_id: s.problem,
    out_of_scope_reason: oos ? (s.oos ?? "no_match") : null,
    flagged: s.flagged ?? false,
    ask_expert: s.askExpert ?? false,
    model_versions: { ...MODELS, llm: s.llm ? LLM_MODEL : null },
    corpus_version: 7,
    images: photos(s.n, cropId, s.n % 3 === 0 ? 1 : 2),
    captured_at: iso(-s.ageH * H - 600_000),
    answered_at: answered,
    reviewed_at: reviewed ? iso(-(s.ageH - (s.reviewedAfterH ?? 0)) * H) : null,
    reviewed_by: reviewed ? "u-agronomist" : null,
    created_at: created,
    updated_at: answered,
    version: 2,
    llm_used: !!s.llm,
    scores: {
      neighbours: s.candidates.map(([pid, score], i) => ({
        image_id: uid("c1a1b2c3", i + 1),
        problem_id: pid,
        similarity: score,
      })),
      thresholds: {
        t1: 0.92,
        agreement: 0.6,
        min_similarity: 0.85,
        config_version: 2,
        crop_id: cropId,
      },
      decision: {
        confidence: s.source === "corpus" ? "high" : "low",
        problem_id: proposal,
        top1,
        agreement: s.candidates.length ? s.candidates[0]![2] / 10 : 0,
        votes,
        in_scope: !oos || s.oos !== "no_match",
      },
      top1,
      votes,
      candidates: s.candidates.map(([problem_id, score, v]) => ({ problem_id, score, votes: v })),
      llm: s.llm,
    },
    reviews: [],
  };
}

/** Five cases in the queue plus 40 days of answered / reviewed history (C62). */
function seedDiagnoses(problems: Problem[]): Diag[] {
  const queue: DiagSeed[] = [
    {
      n: 1,
      crop: "cotton",
      ageH: 26.5,
      status: "provisional",
      source: "llm",
      confidence: "low",
      problem: null,
      llm: {
        model: LLM_MODEL,
        status: "unknown",
        problem_id: null,
        confidence: "low",
        reasoning:
          "Bolls show small dark holes but the photo is too distant to separate pink bollworm damage from aphid honeydew and sooty mould.",
        not_a_plant: false,
      },
      candidates: [
        [P.cottonPbw, 0.884, 5],
        [P.cottonAphids, 0.871, 5],
      ],
      district: "Adilabad",
      season: "kharif",
      stage: "fruiting",
    },
    {
      n: 2,
      crop: "paddy",
      ageH: 19.25,
      status: "provisional",
      source: "llm",
      confidence: "medium",
      problem: P.paddyBlast,
      llm: {
        model: LLM_MODEL,
        status: "answered",
        problem_id: P.paddyBlast,
        confidence: "medium",
        reasoning:
          "Spindle-shaped lesions with grey centres and brown margins on the upper leaves match rice blast better than zinc deficiency, whose spots are rusty and diffuse.",
        not_a_plant: false,
      },
      candidates: [
        [P.paddyBlast, 0.912, 6],
        [P.paddyZinc, 0.897, 4],
      ],
      district: "Warangal",
      season: "kharif",
      stage: "vegetative",
    },
    {
      n: 3,
      crop: "paddy",
      ageH: 8,
      status: "answered",
      source: "corpus",
      confidence: "high",
      problem: P.paddyBlast,
      llm: null,
      candidates: [
        [P.paddyBlast, 0.957, 9],
        [P.paddyZinc, 0.861, 1],
      ],
      flagged: true,
      district: "Karimnagar",
      season: "kharif",
      stage: "flowering",
    },
    {
      n: 4,
      crop: "chilli",
      ageH: 3.2,
      status: "out_of_scope",
      source: null,
      confidence: null,
      problem: null,
      llm: null,
      candidates: [[P.chilliThrips, 0.812, 3]],
      oos: "no_match",
      district: "Guntur",
      season: "kharif",
      stage: "flowering",
    },
    {
      n: 5,
      crop: "tomato",
      ageH: 0.6,
      status: "out_of_scope",
      source: null,
      confidence: null,
      problem: null,
      llm: null,
      candidates: [],
      oos: "unsupported_crop",
      askExpert: true,
      district: "Kolar",
      season: "kharif",
      stage: "fruiting",
    },
  ];
  const history: DiagSeed[] = [];
  const crops = ["paddy", "cotton", "chilli"] as const;
  for (let i = 0; i < 36; i++) {
    const crop = crops[i % 3]!;
    const cands: Record<string, Array<[string, number, number]>> = {
      paddy: [
        [P.paddyBlast, 0.95, 8],
        [P.paddyZinc, 0.86, 2],
      ],
      cotton: [
        [P.cottonPbw, 0.94, 7],
        [P.cottonAphids, 0.88, 3],
      ],
      chilli: [[P.chilliThrips, 0.93, 8]],
    };
    const kind = i % 6;
    const problem = cands[crop]![0]![0];
    history.push({
      n: 100 + i,
      crop,
      ageH: 30 + i * 18,
      status:
        kind < 3
          ? "answered"
          : kind === 3
            ? "confirmed"
            : kind === 4
              ? "corrected"
              : "out_of_scope",
      source: kind < 3 ? "corpus" : kind < 5 ? "agronomist" : null,
      confidence: kind < 5 ? "high" : null,
      problem: kind < 5 ? problem : null,
      llm:
        kind === 3 || kind === 4
          ? {
              model: LLM_MODEL,
              status: "answered",
              problem_id: problem,
              confidence: "medium",
              reasoning: "",
              not_a_plant: false,
            }
          : null,
      candidates: cands[crop]!,
      oos: kind === 5 ? (i % 4 === 1 ? "not_a_plant" : "no_match") : null,
      district: ["Warangal", "Karimnagar", "Raichur", "Nanded"][i % 4]!,
      season: "kharif",
      stage: "vegetative",
      reviewedAfterH: kind >= 3 ? (i % 5 === 0 ? 30 : 6 + (i % 10)) : undefined,
    });
  }
  return [...queue, ...history].map((d) => diag(d, problems));
}

let db: Db = seed();
function state(): Db {
  return db;
}

export function resetMockDiagnosis(): void {
  db = seed();
}

// ---- helpers -----------------------------------------------------------------------------
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
const forbidden = () => problem(403, "forbidden", "Your role does not allow this action.");
const nextId = (prefix: string) => {
  const d = state();
  d.seq += 1;
  return uid(prefix, d.seq);
};

const inQueue = (d: Diag) =>
  !d.reviewed_at &&
  (d.status === "provisional" ||
    d.status === "out_of_scope" ||
    d.ask_expert ||
    (d.flagged && d.status !== "queued"));

function diagOut(d: Diag, now: number, detail: boolean): Json {
  const { ask_expert: _a, ...rest } = d;
  void _a;
  const base: Json = { ...rest };
  if (!detail) {
    delete base.scores;
    delete base.reviews;
    delete base.reviewed_by;
  }
  const ageH = (now - new Date(d.created_at).getTime()) / H;
  return { ...base, age_hours: Math.round(ageH * 100) / 100, overdue: ageH >= ALERT_HOURS };
}

function counts(problemId: string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const i of state().images)
    if (i.problem_id === problemId) out[i.status] = (out[i.status] ?? 0) + 1;
  return out;
}
const problemOut = (p: Problem): Json => ({ ...p, image_counts: counts(p.id) });
const currentVersion = () => Math.max(0, ...state().versions.map((v) => v.version));

function bump(
  actor: MockActor,
  changes: Partial<Version["changes"]>,
  note: string | null,
): Version {
  const v: Version = {
    id: nextId("c2a1b2c3"),
    version: currentVersion() + 1,
    approved_by: actor.id,
    note,
    changes: { problems: [], images: [], retired: [], ...changes },
    created_at: new Date().toISOString(),
  };
  state().versions.push(v);
  return v;
}

function badTransition(from: string, to: string): MockResult {
  return problem(409, "invalid_transition", `Cannot move a ${from} corpus entry to ${to}.`, {
    from,
    to,
  });
}

// ---- diagnoses routes --------------------------------------------------------------------
function reviewQueue(query: URLSearchParams): MockResult {
  const now = Date.now();
  let rows = state().diagnoses.filter(inQueue);
  const crop = query.get("crop_id");
  if (crop) rows = rows.filter((d) => d.crop_id === crop);
  const conf = query.getAll("confidence");
  if (conf.length) rows = rows.filter((d) => conf.includes(d.confidence ?? "low"));
  const minAge = query.get("min_age_hours");
  if (minAge)
    rows = rows.filter((d) => now - new Date(d.created_at).getTime() >= Number(minAge) * H);
  if (query.get("flagged") === "true") rows = rows.filter((d) => d.flagged);
  rows = [...rows].sort(
    (a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id),
  );
  const byConfidence: Record<string, number> = {};
  for (const d of rows)
    byConfidence[d.confidence ?? "low"] = (byConfidence[d.confidence ?? "low"] ?? 0) + 1;
  const limit = Math.min(200, Math.max(1, Number(query.get("limit") ?? 50) || 50));
  const start = Number(query.get("cursor") ?? 0) || 0;
  return ok({
    items: rows.slice(start, start + limit).map((d) => diagOut(d, now, true)),
    next_cursor: start + limit < rows.length ? String(start + limit) : null,
    counts: {
      total: rows.length,
      overdue: rows.filter((d) => now - new Date(d.created_at).getTime() >= ALERT_HOURS * H).length,
      by_confidence: byConfidence,
    },
  });
}

function listDiagnoses(query: URLSearchParams): MockResult {
  const now = Date.now();
  let rows = [...state().diagnoses].sort((a, b) => b.created_at.localeCompare(a.created_at));
  const statuses = query.getAll("status");
  if (statuses.length) rows = rows.filter((d) => statuses.includes(d.status));
  const limit = Math.min(200, Math.max(1, Number(query.get("limit") ?? 50) || 50));
  const start = Number(query.get("cursor") ?? 0) || 0;
  return ok({
    items: rows.slice(start, start + limit).map((d) => {
      const out = diagOut(d, now, false);
      delete out.age_hours;
      delete out.overdue;
      return out;
    }),
    next_cursor: start + limit < rows.length ? String(start + limit) : null,
  });
}

function review(d: Diag, body: Json, actor: MockActor): MockResult {
  const action = String(body.action ?? "");
  const note = typeof body.note === "string" ? body.note.trim() : "";
  if (!["confirm", "correct", "not_diagnosable"].includes(action) || !note || note.length > 2000)
    return problem(422, "validation_error", "Request validation failed.", {
      errors: [{ loc: ["body", note ? "action" : "note"], msg: "invalid", type: "value_error" }],
    });
  if (d.status === "queued")
    return problem(409, "diagnosis_not_reviewable", "The diagnosis is still queued.");
  const now = new Date().toISOString();
  const fromStatus = d.status;
  const fromProblem = d.final_problem_id;
  let target: Problem | null = null;
  if (action === "confirm") {
    target = state().problems.find((p) => p.id === d.final_problem_id) ?? null;
    if (!target)
      return problem(
        422,
        "review_invalid",
        "Nothing to confirm; correct it or mark it not diagnosable.",
      );
  } else if (action === "correct") {
    target = state().problems.find((p) => p.id === body.problem_id) ?? null;
    if (!target || target.crop_id !== d.crop_id || target.status === "retired")
      return problem(422, "review_invalid", "Pick a live corpus problem of the same crop.");
  }
  const imageIds: string[] = [];
  if (body.add_to_corpus === true && target && action !== "not_diagnosable") {
    for (const ph of d.images) {
      const img: Image = {
        id: nextId("c1a1b2c3"),
        problem_id: target.id,
        crop_id: target.crop_id,
        blob_uri: String(ph.blob_uri),
        sha256: String(ph.sha256),
        encoder_name: ENCODER.name,
        encoder_version: ENCODER.version,
        stage: d.crop_stage,
        part: "leaf",
        severity: null,
        region: d.district,
        season: d.season,
        source: "internal",
        status: "reviewed",
        labelled_by: actor.id,
        approved_by: null,
        approved_at: null,
        approved_in_version: null,
        from_diagnosis_id: d.id,
        created_at: now,
        version: 1,
        signed_url: String(ph.signed_url),
      };
      state().images.push(img);
      imageIds.push(img.id);
    }
  }
  if (action === "not_diagnosable") {
    d.status = "out_of_scope";
    d.out_of_scope_reason = "expert_not_diagnosable";
    d.message_key = "diagnosis.out_of_scope.expert_not_diagnosable";
    d.result = null;
    d.final_problem_id = null;
    d.can_buy = false;
    d.cta = "ask_expert";
    d.confidence = null;
  } else {
    d.status = action === "confirm" ? "confirmed" : "corrected";
    d.final_problem_id = target!.id;
    d.confidence = "high";
    d.can_buy = true;
    d.cta = "buy";
    d.out_of_scope_reason = null;
    d.message_key = `diagnosis.result.${d.status}`;
    d.result = resultFor(target, {
      confidence: "high",
      provisional: false,
      canBuy: true,
      messageKey: d.message_key,
    });
  }
  d.source = "agronomist";
  d.provisional = false;
  d.flagged = false;
  d.reviewed_at = now;
  d.reviewed_by = actor.id;
  d.updated_at = now;
  d.version += 1;
  d.reviews.push({
    id: nextId("d2a90000"),
    actor_id: actor.id,
    action,
    from_status: fromStatus,
    to_status: d.status,
    from_problem_id: fromProblem,
    to_problem_id: d.final_problem_id,
    note,
    add_to_corpus: imageIds.length > 0,
    corpus_image_ids: imageIds,
    created_at: now,
  });
  const out = diagOut(d, Date.now(), true);
  delete out.age_hours;
  delete out.overdue;
  return ok(out);
}

function handleDiagnoses(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor,
): MockResult {
  const [, id, action] = path;
  if (id === "review-queue" && method === "GET")
    return QUEUE_READ.includes(actor.role) ? reviewQueue(query) : forbidden();
  if (!DIAG_READ.includes(actor.role)) return forbidden();
  if (!id)
    return method === "GET" ? listDiagnoses(query) : problem(404, "not_found", "No such route.");
  const d = state().diagnoses.find((x) => x.id === id);
  if (!d) return problem(404, "not_found", "Diagnosis not found.");
  if (!action && method === "GET") {
    const detail = ["agronomist", "owner", "director", "tenant_admin"].includes(actor.role);
    const out = diagOut(d, Date.now(), detail);
    delete out.age_hours;
    delete out.overdue;
    return ok(out);
  }
  if (action === "review" && method === "POST")
    return AGRONOMIST.includes(actor.role) ? review(d, body, actor) : forbidden();
  return problem(404, "not_found", `No mock for ${method} /${path.join("/")}`);
}

// ---- corpus routes -----------------------------------------------------------------------
const LANGS = ["en", "te", "kn", "hi", "mr"];

function stringMap(v: unknown): Record<string, string> | null {
  if (!v || typeof v !== "object") return null;
  const out: Record<string, string> = {};
  for (const [k, x] of Object.entries(v as Json)) {
    if (!LANGS.includes(k) || typeof x !== "string") return null;
    out[k] = x;
  }
  return out;
}
function listMap(v: unknown): Record<string, string[]> | null {
  if (v === undefined) return {};
  if (!v || typeof v !== "object") return null;
  const out: Record<string, string[]> = {};
  for (const [k, x] of Object.entries(v as Json)) {
    if (!LANGS.includes(k) || !Array.isArray(x) || !x.every((s) => typeof s === "string"))
      return null;
    out[k] = x as string[];
  }
  return out;
}

/** The catalogue mock's pests (lib/mock/catalog.ts): code, type, crop. */
const PESTS: Record<string, { type: string; crop: string | null }> = {
  "pest-paddy_bph": { type: "pest", crop: "crop-paddy" },
  "pest-paddy_blast": { type: "disease", crop: "crop-paddy" },
  "pest-cotton_pbw": { type: "pest", crop: "crop-cotton" },
  "pest-chilli_thrips": { type: "pest", crop: "crop-chilli" },
  "pest-aphids": { type: "pest", crop: null },
  "pest-zinc_deficiency": { type: "nutrient", crop: null },
};
const CROPS = [
  "crop-paddy",
  "crop-cotton",
  "crop-chilli",
  "crop-maize",
  "crop-tomato",
  "crop-groundnut",
];

function createProblem(body: Json, actor: MockActor): MockResult {
  const pestId = String(body.pest_or_disease_id ?? "");
  const cropId = String(body.crop_id ?? "");
  const pest = PESTS[pestId];
  const names = stringMap(body.names);
  const symptoms = listMap(body.symptoms);
  const cultural = listMap(body.cultural_practices);
  if (!pest) return problem(422, "corpus_problem_invalid", "Unknown pest or disease.");
  if (!CROPS.includes(cropId)) return problem(422, "corpus_problem_invalid", "Unknown crop.");
  if (pest.crop && pest.crop !== cropId)
    return problem(
      422,
      "corpus_problem_invalid",
      "The pest or disease is specific to another crop.",
    );
  if (!names || !names.en?.trim() || !symptoms || !cultural)
    return problem(422, "validation_error", "Request validation failed.", {
      errors: [{ loc: ["body", "names"], msg: "names.en is required", type: "value_error" }],
    });
  const live = state().problems.find(
    (p) => p.crop_id === cropId && p.pest_or_disease_id === pestId && p.status !== "retired",
  );
  if (live)
    return problem(
      409,
      "corpus_problem_exists",
      "This crop already has a live corpus entry for the problem.",
      {
        corpus_problem_id: live.id,
      },
    );
  const now = new Date().toISOString();
  const p: Problem = {
    id: nextId("c0a1b2c3"),
    pest_or_disease_id: pestId,
    pest_code: pestId.replace(/^pest-/, ""),
    crop_id: cropId,
    problem_type: pest.type,
    names,
    symptoms,
    cultural_practices: cultural,
    status: "draft",
    source: body.source === "public" ? "public" : "internal",
    labelled_by: actor.id,
    reviewed_by: null,
    reviewed_at: null,
    approved_by: null,
    approved_at: null,
    approved_in_version: null,
    retired_at: null,
    notes: typeof body.notes === "string" ? body.notes : null,
    created_at: now,
    updated_at: now,
    version: 1,
  };
  state().problems.push(p);
  return ok(problemOut(p), 201);
}

function applyProblem(p: Problem, to: CorpusStatus, actor: MockActor, version: number | null) {
  const now = new Date().toISOString();
  p.status = to;
  if (to === "reviewed") {
    p.reviewed_by = actor.id;
    p.reviewed_at = now;
  } else if (to === "approved") {
    p.approved_by = actor.id;
    p.approved_at = now;
    p.approved_in_version = version;
  } else if (to === "retired") p.retired_at = now;
  p.updated_at = now;
  p.version += 1;
}

function applyImage(i: Image, to: CorpusStatus, actor: MockActor, version: number | null) {
  i.status = to;
  if (to === "approved") {
    i.approved_by = actor.id;
    i.approved_at = new Date().toISOString();
    i.approved_in_version = version;
  }
  i.version += 1;
}

function addImage(p: Problem, body: Json, actor: MockActor): MockResult {
  if (p.status === "retired")
    return problem(409, "corpus_entry_locked", "The corpus problem is retired.");
  const uri = String(body.blob_uri ?? "");
  const blob = state().blobs.get(uri);
  if (!blob)
    return problem(422, "diagnosis_image_missing", "Blob not found; complete the upload first.");
  if (body.sha256 && body.sha256 !== blob.sha256)
    return problem(422, "image_sha_mismatch", "sha256 does not match the uploaded blob.");
  const dup = state().images.find((i) => i.problem_id === p.id && i.sha256 === blob.sha256);
  if (dup)
    return problem(
      409,
      "corpus_image_exists",
      "This image is already in the corpus for the problem.",
      {
        corpus_image_id: dup.id,
      },
    );
  const part = body.part ?? null;
  const severity = body.severity ?? null;
  if (part !== null && !["leaf", "stem", "fruit", "whole"].includes(String(part)))
    return problem(422, "validation_error", "Request validation failed.");
  if (severity !== null && !["low", "medium", "high"].includes(String(severity)))
    return problem(422, "validation_error", "Request validation failed.");
  const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);
  const img: Image = {
    id: nextId("c1a1b2c3"),
    problem_id: p.id,
    crop_id: p.crop_id,
    blob_uri: uri,
    sha256: blob.sha256,
    encoder_name: ENCODER.name,
    encoder_version: ENCODER.version,
    stage: str(body.stage),
    part: part as string | null,
    severity: severity as string | null,
    region: str(body.region),
    season: str(body.season),
    source: body.source === "public" ? "public" : "internal",
    status: "draft",
    labelled_by: actor.id,
    approved_by: null,
    approved_at: null,
    approved_in_version: null,
    from_diagnosis_id: null,
    created_at: new Date().toISOString(),
    version: 1,
    signed_url: blob.dataUrl,
  };
  state().images.push(img);
  return ok(img, 201);
}

function handleCorpus(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor,
): MockResult {
  if (!CORPUS_READ.includes(actor.role)) return forbidden();
  const write = AGRONOMIST.includes(actor.role);
  const [, kind, id, action] = path;
  const note = typeof body.note === "string" && body.note.trim() ? body.note.trim() : null;

  if (kind === "versions" && method === "GET") {
    const items = [...state().versions].sort((a, b) => b.version - a.version);
    return ok({ current: currentVersion(), items });
  }
  if (kind === "approvals" && method === "POST") {
    if (!write) return forbidden();
    const pids = Array.isArray(body.problem_ids) ? [...new Set(body.problem_ids.map(String))] : [];
    const iids = Array.isArray(body.image_ids) ? [...new Set(body.image_ids.map(String))] : [];
    if (!pids.length && !iids.length)
      return problem(422, "corpus_problem_invalid", "Nothing to approve.");
    const ps = pids.map((x) => state().problems.find((p) => p.id === x));
    const is = iids.map((x) => state().images.find((i) => i.id === x));
    if (ps.some((p) => !p) || is.some((i) => !i))
      return problem(404, "not_found", "Corpus entry not found.");
    for (const e of [...ps, ...is])
      if (!TRANSITIONS[e!.status].includes("approved")) return badTransition(e!.status, "approved");
    const v = bump(actor, { problems: pids, images: iids }, note);
    for (const p of ps) applyProblem(p!, "approved", actor, v.version);
    for (const i of is) applyImage(i!, "approved", actor, v.version);
    return ok(v, 201);
  }
  if (kind === "images" && id && action === "transition" && method === "POST") {
    if (!write) return forbidden();
    const img = state().images.find((i) => i.id === id);
    if (!img) return problem(404, "not_found", "Corpus image not found.");
    const to = String(body.to ?? "") as CorpusStatus;
    if (!TRANSITIONS[img.status]?.includes(to)) return badTransition(img.status, to);
    let version: number | null = null;
    if (to === "approved" || img.status === "approved")
      version = bump(
        actor,
        to === "approved" ? { images: [img.id] } : { retired: [img.id] },
        note,
      ).version;
    applyImage(img, to, actor, version);
    return ok(img);
  }
  if (kind !== "problems")
    return problem(404, "not_found", `No mock for ${method} /${path.join("/")}`);

  if (!id) {
    if (method === "POST") return write ? createProblem(body, actor) : forbidden();
    if (method !== "GET") return problem(404, "not_found", "No such route.");
    let rows = [...state().problems];
    const crop = query.get("crop_id");
    if (crop) rows = rows.filter((p) => p.crop_id === crop);
    const statuses = query.getAll("status");
    if (statuses.length) rows = rows.filter((p) => statuses.includes(p.status));
    const source = query.get("source");
    if (source) rows = rows.filter((p) => p.source === source);
    rows.sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
    return ok({ items: rows.map(problemOut), next_cursor: null, corpus_version: currentVersion() });
  }
  const p = state().problems.find((x) => x.id === id);
  if (!p) return problem(404, "not_found", "Corpus problem not found.");
  if (!action) {
    if (method === "GET") return ok(problemOut(p));
    if (method === "PATCH") {
      if (!write) return forbidden();
      if (p.status !== "draft" && p.status !== "reviewed")
        return problem(
          409,
          "corpus_entry_locked",
          "Approved and retired corpus entries are immutable; retire and create a new one.",
        );
      if (body.names !== undefined && body.names !== null) {
        const names = stringMap(body.names);
        if (!names || !names.en?.trim())
          return problem(422, "corpus_problem_invalid", "names.en is required.");
        p.names = names;
      }
      if (body.symptoms !== undefined && body.symptoms !== null) {
        const s = listMap(body.symptoms);
        if (!s) return problem(422, "validation_error", "Request validation failed.");
        p.symptoms = s;
      }
      if (body.cultural_practices !== undefined && body.cultural_practices !== null) {
        const c = listMap(body.cultural_practices);
        if (!c) return problem(422, "validation_error", "Request validation failed.");
        p.cultural_practices = c;
      }
      if ("notes" in body) p.notes = typeof body.notes === "string" ? body.notes : null;
      p.updated_at = new Date().toISOString();
      p.version += 1;
      return ok(problemOut(p));
    }
  }
  if (action === "transition" && method === "POST") {
    if (!write) return forbidden();
    const to = String(body.to ?? "") as CorpusStatus;
    if (!TRANSITIONS[p.status]?.includes(to)) return badTransition(p.status, to);
    let version: number | null = null;
    if (to === "approved" || p.status === "approved")
      version = bump(
        actor,
        to === "approved" ? { problems: [p.id] } : { retired: [p.id] },
        note,
      ).version;
    applyProblem(p, to, actor, version);
    return ok(problemOut(p));
  }
  if (action === "images") {
    if (method === "GET") {
      const statuses = query.getAll("status");
      const items = state()
        .images.filter(
          (i) => i.problem_id === p.id && (!statuses.length || statuses.includes(i.status)),
        )
        .sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
      return ok({ items, next_cursor: null });
    }
    if (method === "POST") return write ? addImage(p, body, actor) : forbidden();
  }
  return problem(404, "not_found", `No mock for ${method} /${path.join("/")}`);
}

// ---- uploads (NF-003) --------------------------------------------------------------------
async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as unknown as ArrayBuffer);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function uploadStatus(u: Upload): Json {
  return {
    upload_id: u.upload_id,
    status: u.blob_uri ? "complete" : "pending",
    chunk_size: u.chunk_size,
    chunk_count: Math.max(1, Math.ceil(u.size_bytes / u.chunk_size)),
    size_bytes: u.size_bytes,
    received_chunks: [...u.chunks.keys()].sort((a, b) => a - b),
    expires_at: u.expires_at,
    blob_uri: u.blob_uri,
  };
}

/**
 * `/uploads*`; `raw` is the request body (JSON for init / complete, bytes for a chunk). Only
 * small images are kept (the mock stores them as data URLs for the signed URL).
 */
export async function handleUploads(
  method: string,
  path: string[],
  raw: ArrayBuffer,
  headers: Headers,
  actor: MockActor | null,
): Promise<MockResult | null> {
  if (path[0] !== "uploads") return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  if (!UPLOAD.includes(actor.role)) return forbidden();
  const [, id, sub, index] = path;
  if (!id && method === "POST") {
    let body: Json = {};
    try {
      body = JSON.parse(new TextDecoder().decode(raw)) as Json;
    } catch {
      /* empty */
    }
    const size = Number(body.size_bytes ?? 0);
    const sha = String(body.sha256 ?? "");
    if (
      !/^[0-9a-f]{64}$/.test(sha) ||
      !(size > 0) ||
      !["image/jpeg", "image/png", "image/webp"].includes(String(body.content_type))
    )
      return problem(422, "validation_error", "Request validation failed.");
    if (size > 2_000_000)
      return problem(422, "upload_too_large", "The mock keeps images up to 2 MB.");
    const u: Upload = {
      upload_id: nextId("ab1d0000"),
      sha256: sha,
      size_bytes: size,
      content_type: String(body.content_type),
      chunk_size: 262_144,
      chunks: new Map(),
      blob_uri: null,
      expires_at: new Date(Date.now() + 24 * H).toISOString(),
    };
    state().uploads.set(u.upload_id, u);
    return ok(uploadStatus(u), 201);
  }
  const u = id ? state().uploads.get(id) : undefined;
  if (!u) return problem(404, "not_found", "Upload not found.");
  if (!sub && method === "GET") return ok(uploadStatus(u));
  if (sub === "chunks" && method === "PUT") {
    if (u.blob_uri) return problem(409, "upload_complete", "The upload is complete.");
    const bytes = new Uint8Array(raw);
    const want = headers.get("x-chunk-sha256");
    if (!want) return problem(422, "chunk_sha_missing", "X-Chunk-Sha256 is required.");
    if ((await sha256Hex(bytes)) !== want)
      return problem(422, "chunk_sha_mismatch", "Chunk sha256 mismatch.");
    u.chunks.set(Number(index), bytes);
    const count = Math.max(1, Math.ceil(u.size_bytes / u.chunk_size));
    const received = [...u.chunks.keys()].sort((a, b) => a - b);
    return ok({
      upload_id: u.upload_id,
      received_chunks: received,
      missing_chunks: Array.from({ length: count }, (_, i) => i).filter((i) => !u.chunks.has(i)),
    });
  }
  if (sub === "complete" && method === "POST") {
    const count = Math.max(1, Math.ceil(u.size_bytes / u.chunk_size));
    if (u.chunks.size < count) return problem(409, "upload_incomplete", "Chunks are missing.");
    const all = new Uint8Array(u.size_bytes);
    let off = 0;
    for (let i = 0; i < count; i++) {
      const c = u.chunks.get(i)!;
      all.set(c, off);
      off += c.length;
    }
    const sha = await sha256Hex(all);
    if (sha !== u.sha256)
      return problem(422, "upload_sha_mismatch", "The file sha256 does not match.");
    u.blob_uri = `gs://farmerapp-dev-media/t1/corpus/${u.upload_id}`;
    const b64 = Buffer.from(all).toString("base64");
    state().blobs.set(u.blob_uri, { dataUrl: `data:${u.content_type};base64,${b64}`, sha256: sha });
    return ok({
      upload_id: u.upload_id,
      blob_uri: u.blob_uri,
      sha256: sha,
      size_bytes: u.size_bytes,
      content_type: u.content_type,
    });
  }
  return problem(404, "not_found", `No mock for ${method} /${path.join("/")}`);
}

/** `/diagnoses*` and `/corpus/*`; null for other routes. */
export function handleDiagnosis(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor | null,
): MockResult | null {
  if (path[0] !== "diagnoses" && path[0] !== "corpus") return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  return path[0] === "diagnoses"
    ? handleDiagnoses(method, path, query, body, actor)
    : handleCorpus(method, path, query, body, actor);
}
