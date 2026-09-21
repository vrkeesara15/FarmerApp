/**
 * In-memory validation flags for the mock API (WC-010, VA-002, VA-003) so C70 / C71 run without
 * apps/api. Mirrors `/v1/flags*` of apps/api/openapi.yaml: `FlagPage` with counts by severity and
 * rule over the filtered set, offset cursors, `FlagDetailOut` with the evidence bundle (records
 * with summaries, GeoJSON points / polygons, signed photo URLs, metrics), history events,
 * comments (`is_subject_explanation` for the flag's subject) and `allowed_transitions`; the
 * SPEC 6.1 state machine with 409 `invalid_transition` (also `reason: note_required`), 409
 * `flag_resolved`, 422 `assignee_invalid`. Holds no real data.
 */
import type { MockActor, MockResult } from "./catalog";
import { recordAudit } from "./admin";

type Json = Record<string, unknown>;
type Status =
  | "open"
  | "in_review"
  | "escalated"
  | "resolved_valid"
  | "resolved_fixed"
  | "resolved_action";

const READ = [
  "owner",
  "director",
  "auditor",
  "cluster_head",
  "store_manager",
  "tenant_admin",
  "field_officer",
];
const REVIEW = ["owner", "director", "auditor", "cluster_head", "store_manager", "tenant_admin"];
const ASSIGN = ["owner", "director", "auditor", "cluster_head", "tenant_admin"];
const TENANT_WIDE = ["owner", "director", "auditor", "tenant_admin"];
const TRANSITIONS: Record<Status, Status[]> = {
  open: ["in_review"],
  in_review: ["resolved_valid", "resolved_fixed", "escalated"],
  escalated: ["resolved_fixed", "resolved_action"],
  resolved_valid: [],
  resolved_fixed: [],
  resolved_action: [],
};
const RESOLVED: Status[] = ["resolved_valid", "resolved_fixed", "resolved_action"];
const LABELS: Partial<Record<Status, string>> = {
  resolved_valid: "false_positive",
  resolved_fixed: "true_positive",
  resolved_action: "true_positive",
};
const LADDER = ["store_manager", "cluster_head", "auditor", "owner"];

interface MockFlag {
  id: string;
  rule_id: string;
  rule_version: number;
  subject_type: string;
  subject_id: string;
  severity: string;
  title: string;
  status: Status;
  owner_id: string | null;
  owner_role: string | null;
  watchers: string[];
  sla_due_at: string;
  escalation_level: number;
  raised_by_mode: string;
  resolution_note: string | null;
  resolved_at: string | null;
  resolved_by: string | null;
  created_at: string;
  version: number;
  scope_store: string | null;
  evidence: Json;
  events: Json[];
  comments: Json[];
}

const H = 3_600_000;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
const fid = (n: number) => `f1a90000-0000-4000-8000-${String(n).padStart(12, "0")}`;

/** A small inline SVG so evidence photos render offline (the API returns signed GCS URLs). */
function photo(label: string, hue: number): Json {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240"><rect width="320" height="240" fill="hsl(${hue},45%,42%)"/><circle cx="160" cy="110" r="52" fill="hsl(${hue},55%,62%)"/><text x="160" y="210" font-family="sans-serif" font-size="20" fill="#fff" text-anchor="middle">${label}</text></svg>`;
  return {
    blob_uri: `gs://farmerapp-dev-media/flags/${label.toLowerCase().replace(/\s+/g, "-")}.jpg`,
    signed_url: `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`,
    signed_url_expires_at: iso(15 * 60_000),
  };
}

const point = (lng: number, lat: number, label?: string): Json => ({
  type: "Point",
  coordinates: [lng, lat],
  ...(label ? { label } : {}),
});
const square = (lng: number, lat: number, d: number): Json => ({
  type: "Polygon",
  coordinates: [
    [
      [lng, lat],
      [lng + d, lat],
      [lng + d, lat + d],
      [lng, lat + d],
      [lng, lat],
    ],
  ],
});

/**
 * Evidence records point at the analytics mock's farmers and officers (lib/mock/analytics.ts),
 * so the record links (`/farmers/{id}`, `/field-team/{id}`) open real mock screens.
 */
export const MOCK_EVIDENCE_FARMER_IDS: Readonly<Record<number, string>> = {
  101: "farmer-001",
  102: "farmer-002",
  2: "farmer-003",
  201: "farmer-004",
  3: "farmer-005",
  4: "farmer-006",
  5: "farmer-007",
  7: "farmer-008",
  701: "farmer-009",
  8: "farmer-010",
};
export const MOCK_EVIDENCE_OFFICER_IDS: Readonly<Record<string, string>> = {
  "u-field_officer": "off-wgl-1",
  "u-fo-lakshmi": "off-wgl-2",
};

function created(flag: Pick<MockFlag, "id" | "owner_id" | "created_at">, n: number): Json {
  return {
    id: `e0000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
    kind: "created",
    actor_id: null,
    from_status: null,
    to_status: "open",
    from_owner_id: null,
    to_owner_id: flag.owner_id,
    label: null,
    note: null,
    created_at: flag.created_at,
  };
}

function seed(): MockFlag[] {
  const base = (
    n: number,
    f: Partial<MockFlag> & Pick<MockFlag, "rule_id" | "severity" | "title">,
  ): MockFlag => {
    const flag: MockFlag = {
      id: fid(n),
      rule_version: 1,
      subject_type: "farmer",
      subject_id: `fa000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
      status: "open",
      owner_id: "u-store_manager",
      owner_role: "store_manager",
      watchers: [],
      sla_due_at: iso(8 * H),
      escalation_level: 0,
      raised_by_mode: "batch",
      resolution_note: null,
      resolved_at: null,
      resolved_by: null,
      created_at: iso(-(20 - n) * H),
      version: 1,
      scope_store: "store-wgl",
      evidence: { records: [], map: { points: [], polygons: [] }, photos: [], metrics: {} },
      events: [],
      comments: [],
      ...f,
    };
    flag.events = [created(flag, n * 10), ...(f.events ?? [])];
    return flag;
  };
  const farmer = (n: number, name: string, village: string) => ({
    type: "farmer",
    id: MOCK_EVIDENCE_FARMER_IDS[n] ?? `fa000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
    summary: { name, village, phone: `+91******${String(4000 + n)}` },
  });
  return [
    base(1, {
      rule_id: "VA-F06",
      severity: "high",
      title: "Registration burst: 11 farmers in 22 minutes",
      subject_type: "employee",
      subject_id: "u-field_officer",
      owner_id: "u-cluster_head",
      owner_role: "cluster_head",
      watchers: ["u-auditor"],
      raised_by_mode: "event",
      sla_due_at: iso(3 * H + 20 * 60_000),
      scope_store: null,
      evidence: {
        records: [
          {
            type: "user",
            id: MOCK_EVIDENCE_OFFICER_IDS["u-field_officer"]!,
            summary: { name: "Ravi Kumar", role: "field_officer" },
          },
          farmer(101, "Ramesh Yadav", "Hanamkonda"),
          farmer(102, "Sita Bai", "Hanamkonda"),
        ],
        map: {
          points: [
            point(79.5941, 17.9689, "Ramesh Yadav"),
            point(79.5952, 17.9701, "Sita Bai"),
            point(79.5967, 17.9676),
          ],
          polygons: [],
        },
        photos: [photo("Meeting 1", 120), photo("Meeting 2", 30)],
        metrics: { registrations: 11, window_minutes: 22, max_registrations: 8 },
      },
      comments: [
        {
          id: "c0000000-0000-4000-8000-000000000001",
          author_id: "u-cluster_head",
          body: "Checking the village meeting schedule with the store.",
          is_subject_explanation: false,
          created_at: iso(-5 * H),
        },
        {
          id: "c0000000-0000-4000-8000-000000000002",
          author_id: "u-field_officer",
          body: "It was a panchayat meeting; all eleven farmers came to the office together.",
          is_subject_explanation: true,
          created_at: iso(-4 * H),
        },
      ],
    }),
    base(2, {
      rule_id: "VA-F02",
      severity: "medium",
      title: "Possible duplicate farmer: same phone as Lakshmi Bai",
      status: "in_review",
      sla_due_at: iso(-2 * H),
      raised_by_mode: "inline",
      evidence: {
        records: [farmer(2, "Laxmi Bai", "Kazipet"), farmer(201, "Lakshmi Bai", "Kazipet")],
        map: {
          points: [point(79.5031, 17.9784), point(79.5033, 17.9786)],
          polygons: [square(79.5025, 17.978, 0.0012), square(79.5028, 17.9782, 0.0012)],
        },
        photos: [],
        metrics: { name_similarity: 0.83, centroid_distance_m: 21 },
      },
      events: [
        {
          id: "e0000000-0000-4000-8000-000000000021",
          kind: "transition",
          actor_id: "u-store_manager",
          from_status: "open",
          to_status: "in_review",
          from_owner_id: "u-store_manager",
          to_owner_id: "u-store_manager",
          label: null,
          note: null,
          created_at: iso(-6 * H),
        },
      ],
    }),
    base(3, {
      rule_id: "VA-F03",
      severity: "medium",
      title: "Farm polygon is 2.4x the declared acreage",
      evidence: {
        records: [
          farmer(3, "Venkat Rao", "Parkal"),
          {
            type: "farm",
            id: "fb000000-0000-4000-8000-000000000003",
            summary: { declared_acres: 2, computed_acres: 4.8 },
          },
        ],
        map: { points: [], polygons: [square(79.698, 18.199, 0.004)] },
        photos: [photo("Boundary", 200)],
        metrics: { declared_acres: 2, measured_acres: 4.8, reasons: ["area_mismatch"] },
      },
    }),
    base(4, {
      rule_id: "VA-F01",
      severity: "high",
      title: "Farmer phone not verified 72 hours after registration",
      status: "escalated",
      owner_id: "u-auditor",
      owner_role: "auditor",
      watchers: ["u-auditor"],
      escalation_level: 1,
      sla_due_at: iso(20 * H),
      evidence: {
        records: [farmer(4, "Mallesh", "Jangaon")],
        map: { points: [point(79.15, 17.72)], polygons: [] },
        photos: [],
        metrics: { hours_unverified: 81 },
      },
    }),
    base(5, {
      rule_id: "VA-F01",
      severity: "low",
      title: "Phone number format looks wrong",
      status: "resolved_valid",
      resolution_note: "Number confirmed on call; landline forwarded to mobile.",
      resolved_at: iso(-2 * H),
      resolved_by: "u-store_manager",
      evidence: {
        records: [farmer(5, "Anjaiah", "Hasanparthy")],
        map: { points: [], polygons: [] },
        photos: [],
        metrics: {},
      },
    }),
    base(6, {
      rule_id: "VA-F06",
      severity: "high",
      title: "One device registered farmers for two officers",
      subject_type: "employee",
      subject_id: "u-fo-lakshmi",
      owner_id: "u-cluster_head",
      owner_role: "cluster_head",
      watchers: ["u-auditor"],
      sla_due_at: iso(-30 * 60_000),
      scope_store: null,
      evidence: {
        records: [
          {
            type: "user",
            id: MOCK_EVIDENCE_OFFICER_IDS["u-fo-lakshmi"]!,
            summary: { name: "Lakshmi Devi", role: "field_officer" },
          },
          {
            type: "user",
            id: MOCK_EVIDENCE_OFFICER_IDS["u-field_officer"]!,
            summary: { name: "Ravi Kumar", role: "field_officer" },
          },
        ],
        map: { points: [point(79.61, 17.99)], polygons: [] },
        photos: [],
        metrics: { device_id: "android-5b2e10", officers: 2 },
      },
    }),
    base(7, {
      rule_id: "VA-F02",
      severity: "low",
      title: "Similar farmer names in one village",
      evidence: {
        records: [farmer(7, "Srinivas", "Kazipet"), farmer(701, "Sreenivas", "Kazipet")],
        map: { points: [], polygons: [] },
        photos: [],
        metrics: { name_similarity: 0.64 },
      },
    }),
    base(8, {
      rule_id: "VA-F03",
      severity: "high",
      title: "Farm boundary overlaps a neighbour by 62%",
      status: "in_review",
      owner_id: "u-owner",
      owner_role: "owner",
      sla_due_at: iso(26 * H),
      evidence: {
        records: [farmer(8, "Yadagiri", "Wardhannapet")],
        map: {
          points: [],
          polygons: [square(79.8, 17.77, 0.003), square(79.8015, 17.7705, 0.003)],
        },
        photos: [],
        metrics: { overlap_share: 0.62, reasons: ["farm_overlap"] },
      },
    }),
  ];
}

let flags: MockFlag[] = seed();
let seq = 1000;

/**
 * Open (unresolved) high / critical flags for the C10 owner home mock — the real API reads the
 * same `flag` table for both screens, so the ids here open in `/flags/{id}`.
 */
export function mockOpenHighSeverityFlags(): Array<{
  id: string;
  rule: string;
  severity: string;
  title: string;
  opened_at: string;
  store_id: string | null;
  officer_id: string | null;
  farmer_id: string | null;
}> {
  return flags
    .filter(
      (f) => !RESOLVED.includes(f.status) && (f.severity === "high" || f.severity === "critical"),
    )
    .map((f) => {
      const records = (f.evidence as { records: Array<{ type: string; id: string }> }).records;
      return {
        id: f.id,
        rule: f.rule_id,
        severity: f.severity,
        title: f.title,
        opened_at: f.created_at,
        store_id: f.scope_store ?? "store-wgl",
        officer_id: records.find((r) => r.type === "user")?.id ?? null,
        farmer_id: records.find((r) => r.type === "farmer")?.id ?? null,
      };
    });
}

export function resetMockFlags(): void {
  flags = seed();
  seq = 1000;
}

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

/** AN-009 `GET /v1/flags/summary`: volume by rule, resolution percentiles, repeat subjects. */
function summary(actor: MockActor, days: number): Json {
  const since = Date.now() - days * 24 * H;
  const rows = visible(actor).filter((f) => Date.parse(f.created_at) >= since);
  const open = (f: MockFlag) => !RESOLVED.includes(f.status);
  const pct = (values: number[], q: number): number | null => {
    if (values.length === 0) return null;
    const sorted = [...values].sort((a, b) => a - b);
    return (
      Math.round(
        sorted[Math.max(0, Math.min(sorted.length - 1, Math.round(q * (sorted.length - 1))))]! *
          100,
      ) / 100
    );
  };
  const hours = (f: MockFlag) =>
    f.resolved_at === null ? null : (Date.parse(f.resolved_at) - Date.parse(f.created_at)) / H;
  const bySeverity: Record<string, number> = {};
  const bySubject: Record<string, number> = {};
  const perRule = new Map<string, MockFlag[]>();
  const subjects = new Map<string, Json>();
  for (const f of rows) {
    bySeverity[f.severity] = (bySeverity[f.severity] ?? 0) + 1;
    bySubject[f.subject_type] = (bySubject[f.subject_type] ?? 0) + 1;
    perRule.set(f.rule_id, [...(perRule.get(f.rule_id) ?? []), f]);
    const key = `${f.subject_type}|${f.subject_id}`;
    const seen = subjects.get(key) as
      | { flags: number; open_flags: number; rules: string[]; last_at: string; title: string }
      | undefined;
    if (!seen)
      subjects.set(key, {
        subject_type: f.subject_type,
        subject_id: f.subject_id,
        title: f.title,
        flags: 1,
        open_flags: open(f) ? 1 : 0,
        rules: [f.rule_id],
        last_at: f.created_at,
      });
    else {
      seen.flags += 1;
      seen.open_flags += open(f) ? 1 : 0;
      if (!seen.rules.includes(f.rule_id)) seen.rules.push(f.rule_id);
      if (f.created_at > seen.last_at) {
        seen.last_at = f.created_at;
        seen.title = f.title;
      }
    }
  }
  const resolvedRows = rows.filter((f) => !open(f));
  const falsePositives = resolvedRows.filter((f) => LABELS[f.status] === "false_positive").length;
  const byRule = [...perRule.entries()]
    .map(([rule_id, list]) => {
      const done = list.filter((f) => !open(f));
      const fp = done.filter((f) => LABELS[f.status] === "false_positive").length;
      const durations = done.map(hours).filter((h): h is number => h !== null);
      return {
        rule_id,
        title: list[0]!.title,
        total: list.length,
        open: list.length - done.length,
        resolved: done.length,
        false_positives: fp,
        false_positive_rate: done.length ? Math.round((fp / done.length) * 1000) / 1000 : null,
        median_resolution_hours: pct(durations, 0.5),
        p90_resolution_hours: pct(durations, 0.9),
        precision: done.length
          ? Math.round(((done.length - fp) / done.length) * 1000) / 1000
          : null,
        precision_resolved: done.length,
      };
    })
    .sort((a, b) => b.total - a.total || a.rule_id.localeCompare(b.rule_id));
  const all = resolvedRows.map(hours).filter((h): h is number => h !== null);
  return {
    days,
    from_date: new Date(since).toISOString().slice(0, 10),
    to_date: new Date().toISOString().slice(0, 10),
    total: rows.length,
    open: rows.filter(open).length,
    resolved: resolvedRows.length,
    overdue: rows.filter((f) => open(f) && Date.parse(f.sla_due_at) < Date.now()).length,
    by_severity: bySeverity,
    by_subject_type: bySubject,
    by_rule: byRule,
    median_resolution_hours: pct(all, 0.5),
    p90_resolution_hours: pct(all, 0.9),
    false_positive_rate: resolvedRows.length
      ? Math.round((falsePositives / resolvedRows.length) * 1000) / 1000
      : null,
    repeat_min: 2,
    repeat_subjects: [...subjects.values()]
      .filter((s) => (s as { flags: number }).flags >= 2)
      .sort((a, b) => (b as { flags: number }).flags - (a as { flags: number }).flags),
    precision_floor: 0.3,
    precision_window_weeks: 4,
  };
}

function visible(actor: MockActor): MockFlag[] {
  if (TENANT_WIDE.includes(actor.role)) return flags;
  if (actor.role === "field_officer")
    return flags.filter((f) => f.subject_type === "employee" && f.subject_id === actor.id);
  if (actor.role === "store_manager")
    return flags.filter(
      (f) =>
        (f.subject_type === "farmer" && f.scope_store === "store-wgl") || f.owner_id === actor.id,
    );
  if (actor.role === "cluster_head") return flags; // the mock tenant has one cluster with flags
  return [];
}

const isOverdue = (f: MockFlag, now: number) =>
  !RESOLVED.includes(f.status) && new Date(f.sla_due_at).getTime() < now;

function out(f: MockFlag, now: number): Json {
  const { scope_store: _s, evidence: _e, events: _v, comments: _c, ...rest } = f;
  void _s;
  void _e;
  void _v;
  void _c;
  return { ...rest, overdue: isOverdue(f, now) };
}

function detail(f: MockFlag, actor: MockActor, now: number): Json {
  const reviewer = REVIEW.includes(actor.role);
  const ev = f.evidence as { records: Json[] };
  return {
    ...out(f, now),
    evidence: {
      ...f.evidence,
      records: ev.records.map((r) => (reviewer ? r : { type: r.type, id: r.id, summary: {} })),
    },
    events: f.events,
    comments: f.comments,
    allowed_transitions: reviewer ? [...TRANSITIONS[f.status]].sort() : [],
  };
}

function list(actor: MockActor, query: URLSearchParams): MockResult {
  const now = Date.now();
  let rows = visible(actor);
  const statuses = query.getAll("status");
  if (statuses.length) rows = rows.filter((f) => statuses.includes(f.status));
  const severities = query.getAll("severity");
  if (severities.length) rows = rows.filter((f) => severities.includes(f.severity));
  const rule = query.get("rule_id");
  if (rule) rows = rows.filter((f) => f.rule_id === rule);
  const subject = query.get("subject_type");
  if (subject) rows = rows.filter((f) => f.subject_type === subject);
  if (query.get("owner") === "me")
    rows = rows.filter((f) => f.owner_id === actor.id || f.watchers.includes(actor.id));
  if (query.get("overdue") === "true") rows = rows.filter((f) => isOverdue(f, now));
  rows = [...rows].sort(
    (a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id),
  );
  const counts = {
    total: rows.length,
    by_severity: {} as Record<string, number>,
    by_rule: {} as Record<string, number>,
  };
  for (const f of rows) {
    counts.by_severity[f.severity] = (counts.by_severity[f.severity] ?? 0) + 1;
    counts.by_rule[f.rule_id] = (counts.by_rule[f.rule_id] ?? 0) + 1;
  }
  const limit = Math.min(200, Math.max(1, Number(query.get("limit") ?? 50) || 50));
  const start = Number(query.get("cursor") ?? 0) || 0;
  const items = rows.slice(start, start + limit).map((f) => out(f, now));
  return ok({
    items,
    next_cursor: start + limit < rows.length ? String(start + limit) : null,
    counts,
  });
}

/** `/flags*`; null for other routes. */
export function handleFlags(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor | null,
): MockResult | null {
  if (path[0] !== "flags") return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  if (!READ.includes(actor.role))
    return problem(403, "forbidden", "Your role does not allow this action.");
  const [, id, action] = path;
  if (id === "summary" && method === "GET") {
    if (!REVIEW.includes(actor.role))
      return problem(403, "forbidden", "Your role does not allow this action.");
    return ok(summary(actor, Number(query.get("days") ?? 90)));
  }
  if (!id)
    return method === "GET" ? list(actor, query) : problem(404, "not_found", "No such route.");
  const flag = visible(actor).find((f) => f.id === id);
  if (!flag) return problem(404, "not_found", "Flag not found.");
  const now = Date.now();

  if (!action && method === "GET") return ok(detail(flag, actor, now));

  if (action === "transition" && method === "POST") {
    if (!REVIEW.includes(actor.role))
      return problem(403, "forbidden", "Your role does not allow this action.");
    const to = String(body.to ?? "") as Status;
    const note = typeof body.note === "string" ? body.note : null;
    if (!TRANSITIONS[flag.status].includes(to))
      return problem(
        409,
        "invalid_transition",
        `A flag in '${flag.status}' cannot move to '${to}'.`,
        {
          from: flag.status,
          to,
          allowed: [...TRANSITIONS[flag.status]].sort(),
        },
      );
    if (to !== "in_review" && !(note && note.trim()))
      return problem(409, "invalid_transition", "Resolving or escalating a flag needs a note.", {
        from: flag.status,
        to,
        reason: "note_required",
      });
    const from = flag.status;
    const fromOwner = flag.owner_id;
    flag.status = to;
    if (RESOLVED.includes(to)) {
      flag.resolved_at = new Date(now).toISOString();
      flag.resolved_by = actor.id;
      flag.resolution_note = note;
    }
    if (to === "escalated" && LADDER.indexOf(flag.owner_role ?? "") < LADDER.indexOf("auditor")) {
      flag.owner_id = "u-auditor";
      flag.owner_role = "auditor";
      flag.escalation_level += 1;
    }
    flag.version += 1;
    seq += 1;
    flag.events.push({
      id: `e0000000-0000-4000-8000-${String(seq).padStart(12, "0")}`,
      kind: "transition",
      actor_id: actor.id,
      from_status: from,
      to_status: to,
      from_owner_id: fromOwner,
      to_owner_id: flag.owner_id,
      label: LABELS[to] ?? null,
      note,
      created_at: new Date(now).toISOString(),
    });
    recordAudit(actor, "flag.update", "flag", flag.id, { status: from }, { status: to });
    return ok(detail(flag, actor, now));
  }

  if (action === "comments" && method === "POST") {
    const text = typeof body.body === "string" ? body.body.trim() : "";
    if (!text || text.length > 2000)
      return problem(422, "validation_error", "Request validation failed.", {
        errors: [{ loc: ["body", "body"], msg: "1-2000 characters", type: "value_error" }],
      });
    if (RESOLVED.includes(flag.status))
      return problem(409, "flag_resolved", "This flag is resolved.");
    seq += 1;
    const comment = {
      id: `c0000000-0000-4000-8000-${String(seq).padStart(12, "0")}`,
      author_id: actor.id,
      body: text,
      is_subject_explanation: flag.subject_type === "employee" && flag.subject_id === actor.id,
      created_at: new Date(now).toISOString(),
    };
    flag.comments.push(comment);
    return ok(comment, 201);
  }

  if (action === "assign" && method === "POST") {
    if (!ASSIGN.includes(actor.role))
      return problem(403, "forbidden", "Your role does not allow this action.");
    if (RESOLVED.includes(flag.status))
      return problem(409, "flag_resolved", "This flag is resolved.");
    const userId = String(body.user_id ?? "");
    const role = /^u-([a-z_]+)$/.exec(userId)?.[1];
    if (!role || !REVIEW.includes(role))
      return problem(422, "assignee_invalid", "Assign to an active reviewer.");
    seq += 1;
    flag.events.push({
      id: `e0000000-0000-4000-8000-${String(seq).padStart(12, "0")}`,
      kind: "assigned",
      actor_id: actor.id,
      from_status: flag.status,
      to_status: flag.status,
      from_owner_id: flag.owner_id,
      to_owner_id: userId,
      label: null,
      note: typeof body.note === "string" ? body.note : null,
      created_at: new Date(now).toISOString(),
    });
    flag.owner_id = userId;
    flag.owner_role = role;
    return ok(detail(flag, actor, now));
  }
  return problem(404, "not_found", `No mock for ${method} /${path.join("/")}`);
}
