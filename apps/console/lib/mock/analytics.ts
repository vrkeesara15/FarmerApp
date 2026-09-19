/**
 * Analytics fixtures for the mock API (app/api/mock) so the console and Playwright run offline.
 * Mirrors `/v1/analytics/*` of apps/api/openapi.yaml (M4 analytics API, docs/prs/M4-analytics-api.md):
 * the same shapes, role lists (store manager 403 on the day replay, field officer own row),
 * AN-011 filters with the API's problems (`invalid_date_range`, `invalid_filter_combination`,
 * `not_found`), echoed `filters`, and cursor pagination on the farmer directory.
 *
 * Data: 24 stores in Telangana, Karnataka and Maharashtra (3 clusters), 30 officers, 72
 * farmers. Every figure is a deterministic function of (entity, IST day), so any date range
 * works and reloads show the same numbers. Holds no real data.
 */
import type { MockActor, MockResult } from "./catalog";

type Json = Record<string, unknown>;

// ---- deterministic noise -----------------------------------------------------------------
function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}
/** Uniform [0, 1) from a key. */
const rnd = (key: string) => (hash(key) % 100000) / 100000;
const pick = <T>(arr: readonly T[], key: string): T => arr[hash(key) % arr.length]!;

// ---- dates (IST days) --------------------------------------------------------------------
const DAY_MS = 86_400_000;
const IST_MS = 330 * 60_000;
const todayIst = () => new Date(Date.now() + IST_MS).toISOString().slice(0, 10);
const addDays = (d: string, n: number) =>
  new Date(Date.parse(`${d}T00:00:00Z`) + n * DAY_MS).toISOString().slice(0, 10);
const daysIn = (from: string, to: string) =>
  Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS) + 1;
const isDate = (s: string | null): s is string =>
  !!s && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));
function dayList(from: string, to: string): string[] {
  const out: string[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) out.push(d);
  return out;
}
const lastYear = (d: string) => {
  const y = Number(d.slice(0, 4)) - 1;
  const md = d.slice(5) === "02-29" ? "02-28" : d.slice(5);
  return `${y}-${md}`;
};
/** IST wall-clock time on a day -> UTC ISO. */
const istAt = (day: string, hh: number, mm: number) =>
  new Date(Date.parse(`${day}T00:00:00Z`) + (hh * 60 + mm) * 60_000 - IST_MS).toISOString();
const weekday = (d: string) => new Date(`${d}T00:00:00Z`).getUTCDay();

// ---- master data ---------------------------------------------------------------------------
interface Store {
  id: string;
  code: string;
  name: string;
  district: string;
  cluster_id: string;
  lat: number;
  lon: number;
}
interface Officer {
  id: string;
  name: string;
  phone: string;
  store_id: string;
  cluster_id: string;
}
interface Farmer {
  id: string;
  name: string;
  phone: string;
  village_id: string;
  village: string;
  district: string;
  store_id: string;
  registered_by: string;
  crop_ids: string[];
  stage: string;
  acres: number;
  lat: number;
  lon: number;
}

export const MOCK_CLUSTERS = [
  { id: "cluster-tg", name: "Telangana" },
  { id: "cluster-ka", name: "Karnataka" },
  { id: "cluster-mh", name: "Maharashtra" },
] as const;

const STORE_SEED: Array<[string, string, string, number, number]> = [
  ["WGL", "Warangal", "cluster-tg", 17.97, 79.59],
  ["KNR", "Karimnagar", "cluster-tg", 18.44, 79.13],
  ["NZB", "Nizamabad", "cluster-tg", 18.67, 78.09],
  ["KMM", "Khammam", "cluster-tg", 17.25, 80.15],
  ["NLG", "Nalgonda", "cluster-tg", 17.05, 79.27],
  ["SDP", "Siddipet", "cluster-tg", 18.1, 78.85],
  ["MBN", "Mahabubnagar", "cluster-tg", 16.74, 78.0],
  ["ADB", "Adilabad", "cluster-tg", 19.66, 78.53],
  ["HBL", "Hubballi", "cluster-ka", 15.36, 75.12],
  ["BGM", "Belagavi", "cluster-ka", 15.85, 74.5],
  ["RCR", "Raichur", "cluster-ka", 16.21, 77.36],
  ["BLY", "Ballari", "cluster-ka", 15.14, 76.92],
  ["DVG", "Davanagere", "cluster-ka", 14.46, 75.92],
  ["GDG", "Gadag", "cluster-ka", 15.43, 75.63],
  ["KLB", "Kalaburagi", "cluster-ka", 17.33, 76.83],
  ["BJP", "Vijayapura", "cluster-ka", 16.83, 75.71],
  ["NGP", "Nagpur", "cluster-mh", 21.15, 79.09],
  ["AKL", "Akola", "cluster-mh", 20.7, 77.0],
  ["AMT", "Amravati", "cluster-mh", 20.93, 77.75],
  ["YTL", "Yavatmal", "cluster-mh", 20.39, 78.12],
  ["NED", "Nanded", "cluster-mh", 19.15, 77.32],
  ["LTR", "Latur", "cluster-mh", 18.4, 76.56],
  ["JLN", "Jalna", "cluster-mh", 19.84, 75.88],
  ["WRD", "Wardha", "cluster-mh", 20.74, 78.6],
];

export const MOCK_STORES: Store[] = STORE_SEED.map(([code, district, cluster_id, lat, lon]) => ({
  id: `store-${code.toLowerCase()}`,
  code,
  name: `FCC ${district}`,
  district,
  cluster_id,
  lat,
  lon,
}));

const OFFICER_NAMES = [
  "Ravi Kumar",
  "Srinivas Reddy",
  "Lakshmi Devi",
  "Mahesh Goud",
  "Anil Naik",
  "Kavitha Rao",
  "Praveen Yadav",
  "Swathi Chary",
  "Basavaraj Patil",
  "Manjunath Hegde",
  "Shivakumar B",
  "Rekha Kulkarni",
  "Veeresh Angadi",
  "Nagaraj Gowda",
  "Sunita Desai",
  "Mallikarjun H",
  "Ganesh Pawar",
  "Sachin Deshmukh",
  "Pooja Jadhav",
  "Vijay Shinde",
  "Rahul Wankhede",
  "Snehal More",
  "Amol Thakre",
  "Kiran Bhosale",
  "Suresh Babu",
  "Madhavi Latha",
  "Prakash Shetty",
  "Deepak Chavan",
  "Venkatesh M",
  "Harish Kamble",
];

export const MOCK_OFFICERS: Officer[] = OFFICER_NAMES.map((name, i) => {
  const store = MOCK_STORES[i < 24 ? i : (i - 24) * 4]!;
  const n = i < 24 ? 1 : 2;
  return {
    id: `off-${store.code.toLowerCase()}-${n}`,
    name,
    phone: `+9194400${String(10000 + i).slice(-5)}`,
    store_id: store.id,
    cluster_id: store.cluster_id,
  };
});

/** The mock field officer (role `field_officer`) is this officer; the store manager runs WGL. */
export const MOCK_SELF_OFFICER_ID = "off-wgl-1";
export const MOCK_MANAGER_STORE_ID = "store-wgl";
export const MOCK_HEAD_CLUSTER_ID = "cluster-tg";

const CROP_IDS = [
  "crop-paddy",
  "crop-cotton",
  "crop-chilli",
  "crop-maize",
  "crop-tomato",
  "crop-groundnut",
];
const CROP_NAMES: Record<string, string> = {
  "crop-paddy": "Paddy",
  "crop-cotton": "Cotton",
  "crop-chilli": "Chilli",
  "crop-maize": "Maize",
  "crop-tomato": "Tomato",
  "crop-groundnut": "Groundnut",
};
const STAGES = ["sown", "vegetative", "flowering", "fruiting", "maturity", "harvested"];
const FIRST = [
  "Ramesh",
  "Sridevi",
  "Venkat",
  "Yadagiri",
  "Anjali",
  "Mallesh",
  "Shankarappa",
  "Girija",
  "Hanumanth",
  "Dattatray",
  "Savita",
  "Pandurang",
];
const LAST = ["Reddy", "Goud", "Patil", "Naik", "Gowda", "Pawar", "Rao", "Jadhav", "Kumar"];
const VILLAGES = ["Hanamkonda", "Dharmaram", "Kodur", "Pedda Palli", "Mudhol", "Wadgaon"];

export const MOCK_FARMERS: Farmer[] = MOCK_STORES.flatMap((store, si) =>
  [0, 1, 2].map((k) => {
    const idx = si * 3 + k;
    const id = `farmer-${String(idx + 1).padStart(3, "0")}`;
    const officers = MOCK_OFFICERS.filter((o) => o.store_id === store.id);
    const village = `${pick(VILLAGES, id)} (${store.district})`;
    const crops = [pick(CROP_IDS, `${id}:c1`)];
    const second = pick(CROP_IDS, `${id}:c2`);
    if (second !== crops[0] && rnd(`${id}:two`) > 0.5) crops.push(second);
    return {
      id,
      name: `${FIRST[idx % FIRST.length]} ${LAST[(idx * 7) % LAST.length]}`,
      phone: `+9198480${String(20000 + idx).slice(-5)}`,
      village_id: `village-${store.code.toLowerCase()}-${k}`,
      village,
      district: store.district,
      store_id: store.id,
      registered_by: officers[k % officers.length]!.id,
      crop_ids: crops,
      stage: pick(STAGES, `${id}:stage`),
      acres: Math.round((1 + rnd(`${id}:acres`) * 6) * 10) / 10,
      lat: store.lat + (rnd(`${id}:lat`) - 0.5) * 0.2,
      lon: store.lon + (rnd(`${id}:lon`) - 0.5) * 0.2,
    };
  }),
);

// ---- per-day facts -------------------------------------------------------------------------
const yearFactor = (d: string) => Math.max(0.5, 1 - 0.15 * (2026 - Number(d.slice(0, 4))));

function storeDay(storeId: string, day: string) {
  const base = 20_000 + rnd(`${storeId}:base`) * 70_000; // rupees per day
  const wd = weekday(day) === 0 ? 0.35 : 1;
  const noise = 0.75 + rnd(`${storeId}:${day}:rev`) * 0.5;
  const revenue = Math.round(base * wd * noise * yearFactor(day)) * 100;
  const shareBase = 0.25 + rnd(`${storeId}:share`) * 0.3;
  const share = Math.min(
    0.9,
    Math.max(0.05, shareBase + (rnd(`${storeId}:${day}:sh`) - 0.5) * 0.1),
  );
  return { revenue, own: Math.round(revenue * share) };
}

function storeLevels(storeId: string, day: string) {
  const outstanding =
    Math.round(
      (200_000 + rnd(`${storeId}:credit`) * 600_000) * (0.9 + rnd(`${storeId}:${day}:cr`) * 0.2),
    ) * 100;
  const overdueRatio = 0.2 + rnd(`${storeId}:od`) * 0.25;
  const overdue = Math.round(outstanding * overdueRatio);
  const b = [0.45, 0.25, 0.18, 0.12];
  const buckets = {
    "0_30": Math.round(overdue * b[0]!),
    "31_60": Math.round(overdue * b[1]!),
    "61_90": Math.round(overdue * b[2]!),
    "90_plus":
      overdue -
      Math.round(overdue * b[0]!) -
      Math.round(overdue * b[1]!) -
      Math.round(overdue * b[2]!),
  };
  const activeFarmers = Math.round(
    150 + rnd(`${storeId}:af`) * 250 + rnd(`${storeId}:${day}:af`) * 20,
  );
  const openFlags = Math.floor(rnd(`${storeId}:${day}:fl`) * 4);
  return { outstanding, overdue, buckets, activeFarmers, openFlags };
}

function officerDay(officerId: string, day: string) {
  const onDuty = weekday(day) !== 0 && rnd(`${officerId}:${day}:duty`) > 0.15;
  if (!onDuty) return null;
  const quality = 0.5 + rnd(`${officerId}:q`) * 0.45;
  const visits = 3 + Math.floor(rnd(`${officerId}:${day}:v`) * 6);
  const verified = Math.round(visits * quality);
  return {
    visits,
    verified,
    confirmed: Math.round(visits * (0.4 + rnd(`${officerId}:conf`) * 0.5)),
    km: Math.round((15 + rnd(`${officerId}:${day}:km`) * 45) * 10) / 10,
    timeOnFarm: verified * (900 + Math.floor(rnd(`${officerId}:${day}:tof`) * 900)),
    registrations: rnd(`${officerId}:${day}:reg`) > 0.7 ? 1 : 0,
    collections: Math.round(rnd(`${officerId}:${day}:col`) * 15_000) * 100,
  };
}

// ---- scope & filters -----------------------------------------------------------------------
interface Scope {
  from: string;
  to: string;
  days: number;
  stores: Store[];
  officers: Officer[];
  /** Fraction of sales attributed (crop / officer narrowing). */
  factor: number;
  echo: Json;
  role: string;
}

const HOME_ROLES = [
  "owner",
  "director",
  "tenant_admin",
  "auditor",
  "cluster_head",
  "store_manager",
];
const TEAM_ROLES = [...HOME_ROLES, "field_officer"];
const REPLAY_ROLES = [
  "owner",
  "director",
  "tenant_admin",
  "auditor",
  "cluster_head",
  "field_officer",
];
const FARMER_ROLES = [...HOME_ROLES, "field_officer"];
const STORE_ROLES = [...HOME_ROLES, "accountant"];

function problem(status: number, code: string, detail: string): MockResult {
  return {
    status,
    json: { type: `https://farmerapp.dev/problems/${code}`, title: code, status, code, detail },
    headers: { "content-type": "application/problem+json" },
  };
}
const ok = (json: unknown): MockResult => ({ status: 200, json });

function resolveScope(role: string, q: URLSearchParams): Scope | MockResult {
  const today = todayIst();
  const rawFrom = q.get("from");
  const rawTo = q.get("to");
  if ((rawFrom && !isDate(rawFrom)) || (rawTo && !isDate(rawTo)))
    return problem(422, "validation_error", "from / to must be YYYY-MM-DD.");
  const to = rawTo ?? today;
  const from = rawFrom ?? addDays(to, -29);
  if (from > to || daysIn(from, to) > 366)
    return problem(422, "invalid_date_range", "from must be <= to and the range at most 366 days.");

  let stores = MOCK_STORES;
  let officers = MOCK_OFFICERS;
  let scope = "tenant";
  if (role === "cluster_head") {
    scope = "cluster";
    stores = stores.filter((s) => s.cluster_id === MOCK_HEAD_CLUSTER_ID);
  } else if (role === "store_manager") {
    scope = "store";
    stores = stores.filter((s) => s.id === MOCK_MANAGER_STORE_ID);
  } else if (role === "field_officer") {
    scope = "own";
    officers = officers.filter((o) => o.id === MOCK_SELF_OFFICER_ID);
    stores = stores.filter((s) => s.id === officers[0]!.store_id);
  }
  officers = officers.filter((o) => stores.some((s) => s.id === o.store_id));
  const roleStores = stores;
  const roleOfficers = officers;

  const clusterId = q.get("cluster_id");
  const storeId = q.get("store_id");
  const officerId = q.get("officer_id");
  const cropId = q.get("crop_id");
  let factor = 1;
  if (clusterId) {
    if (!roleStores.some((s) => s.cluster_id === clusterId))
      return problem(404, "not_found", "Cluster not found.");
    stores = stores.filter((s) => s.cluster_id === clusterId);
    officers = officers.filter((o) => o.cluster_id === clusterId);
  }
  if (storeId) {
    const store = roleStores.find((s) => s.id === storeId);
    if (!store) return problem(404, "not_found", "Store not found.");
    if (clusterId && store.cluster_id !== clusterId)
      return problem(
        422,
        "invalid_filter_combination",
        "The store is not in the selected cluster.",
      );
    stores = [store];
    officers = officers.filter((o) => o.store_id === storeId);
  }
  if (officerId) {
    const officer = roleOfficers.find((o) => o.id === officerId);
    if (!officer) return problem(404, "not_found", "Officer not found.");
    if (!officers.some((o) => o.id === officerId))
      return problem(
        422,
        "invalid_filter_combination",
        "The officer is not in the selected store or cluster.",
      );
    officers = [officer];
    stores = stores.filter((s) => s.id === officer.store_id);
    factor *= 0.18;
  }
  if (cropId) {
    if (!CROP_IDS.includes(cropId)) return problem(404, "not_found", "Crop not found.");
    factor *= 0.25 + rnd(`${cropId}:share`) * 0.35;
  }
  return {
    from,
    to,
    days: daysIn(from, to),
    stores,
    officers,
    factor,
    role,
    echo: {
      from,
      to,
      cluster_id: clusterId,
      store_id: storeId,
      officer_id: officerId,
      crop_id: cropId,
      days: daysIn(from, to),
      scope,
    },
  };
}

// ---- aggregates ----------------------------------------------------------------------------
interface Bucket {
  start: string;
  end: string;
  days: string[];
}
function buckets(from: string, to: string, weekly: boolean): Bucket[] {
  const days = dayList(from, to);
  const size = weekly ? 7 : 1;
  const out: Bucket[] = [];
  for (let i = 0; i < days.length; i += size) {
    const slice = days.slice(i, i + size);
    out.push({ start: slice[0]!, end: slice[slice.length - 1]!, days: slice });
  }
  return out;
}

function sales(sc: Scope, days: string[]) {
  let revenue = 0;
  let own = 0;
  for (const s of sc.stores)
    for (const d of days) {
      const x = storeDay(s.id, d);
      revenue += x.revenue;
      own += x.own;
    }
  return { revenue: Math.round(revenue * sc.factor), own: Math.round(own * sc.factor) };
}

function levels(sc: Scope, day: string) {
  let outstanding = 0;
  let overdue = 0;
  let activeFarmers = 0;
  let openFlags = 0;
  const b: Record<string, number> = { "0_30": 0, "31_60": 0, "61_90": 0, "90_plus": 0 };
  for (const s of sc.stores) {
    const l = storeLevels(s.id, day);
    outstanding += l.outstanding;
    overdue += l.overdue;
    activeFarmers += l.activeFarmers;
    openFlags += l.openFlags;
    for (const k of Object.keys(b)) b[k]! += l.buckets[k as keyof typeof l.buckets];
  }
  const f = sc.factor;
  for (const k of Object.keys(b)) b[k] = Math.round(b[k]! * f);
  return {
    outstanding: Math.round(outstanding * f),
    overdue: Math.round(overdue * f),
    activeFarmers: Math.round(activeFarmers * f),
    openFlags: sc.officers.length === 1 ? Math.min(openFlags, 2) : openFlags,
    buckets: b,
  };
}

function verifiedVisits(sc: Scope, days: string[]) {
  let n = 0;
  for (const o of sc.officers) for (const d of days) n += officerDay(o.id, d)?.verified ?? 0;
  return n;
}

function scorecard(o: Officer, sc: Scope, locationVisible: boolean) {
  const days = dayList(sc.from, sc.to);
  let duty = 0;
  let visits = 0;
  let verified = 0;
  let confirmed = 0;
  let km = 0;
  let tof = 0;
  let reg = 0;
  let col = 0;
  for (const d of days) {
    const x = officerDay(o.id, d);
    if (!x) continue;
    duty += 1;
    visits += x.visits;
    verified += x.verified;
    confirmed += x.confirmed;
    km += x.km;
    tof += x.timeOnFarm;
    reg += x.registrations;
    col += x.collections;
  }
  const visited = Math.min(Math.round(visits * 0.7), 40 + Math.floor(rnd(`${o.id}:pool`) * 80));
  const converted = Math.round(visited * (0.15 + rnd(`${o.id}:conv`) * 0.3));
  const trend = buckets(sc.from, sc.to, true).map((b) => ({
    start: b.start,
    end: b.end,
    value: b.days.reduce((n, d) => n + (officerDay(o.id, d)?.verified ?? 0), 0),
  }));
  return {
    officer_id: o.id,
    name: o.name,
    store_id: o.store_id,
    cluster_id: o.cluster_id,
    rank: 0,
    duty_days: duty,
    visits,
    verified_visits: verified,
    verified_visits_per_day: duty ? Math.round((verified / duty) * 100) / 100 : null,
    unique_farmers_reached: Math.min(verified, Math.round(visited * 0.8)),
    new_registrations: reg,
    confirmation_rate: visits ? Math.round((confirmed / visits) * 1000) / 1000 : null,
    avg_time_on_farm_s: verified ? Math.round(tof / verified) : null,
    time_on_farm_s: tof,
    km_per_day: locationVisible ? (duty ? Math.round((km / duty) * 10) / 10 : null) : null,
    conversion_rate: visited ? Math.round((converted / visited) * 1000) / 1000 : null,
    converted_farmers: converted,
    visited_farmers: visited,
    collections_paise: col,
    flags: Math.floor(rnd(`${o.id}:${sc.to}:flags`) * 3),
    trend,
  };
}

function rankRows<
  T extends {
    verified_visits_per_day: number | null;
    verified_visits: number;
    name: string;
    rank: number;
  },
>(rows: T[]): T[] {
  const sorted = [...rows].sort(
    (a, b) =>
      (b.verified_visits_per_day ?? -1) - (a.verified_visits_per_day ?? -1) ||
      b.verified_visits - a.verified_visits ||
      a.name.localeCompare(b.name),
  );
  sorted.forEach((r, i) => (r.rank = i + 1));
  return sorted;
}

// ---- endpoints -----------------------------------------------------------------------------
const TARGETS = {
  revenue_paise_per_store_month: 18_00_000_00,
  own_brand_share: 0.45,
  verified_visits_per_officer_month: 120,
  active_farmers_per_store: 300,
};

function ownerHome(sc: Scope) {
  const weekly = sc.days > 31;
  const bks = buckets(sc.from, sc.to, weekly);
  const all = dayList(sc.from, sc.to);
  const lyDays = all.map(lastYear);
  const cur = sales(sc, all);
  const ly = sales(sc, lyDays);
  const lvl = levels(sc, sc.to);
  const lvlLy = levels(sc, lastYear(sc.to));
  const scale = sc.days / 30;
  const revSeries = bks.map((b) => ({
    start: b.start,
    end: b.end,
    value: sales(sc, b.days).revenue,
  }));
  const shareSeries = bks.map((b) => {
    const s = sales(sc, b.days);
    return {
      start: b.start,
      end: b.end,
      value: s.revenue ? Math.round((s.own / s.revenue) * 1000) / 1000 : null,
    };
  });
  const lySeries = bks.map((b) => ({
    start: b.start,
    end: b.end,
    value: sales(sc, b.days.map(lastYear)).revenue,
  }));
  const levelSeries = (fn: (l: ReturnType<typeof levels>) => number) =>
    bks.map((b) => ({ start: b.start, end: b.end, value: fn(levels(sc, b.end)) }));
  const visitsSeries = bks.map((b) => ({
    start: b.start,
    end: b.end,
    value: verifiedVisits(sc, b.days),
  }));
  const kpis = [
    {
      key: "revenue",
      unit: "paise",
      value: cur.revenue,
      target: Math.round(
        TARGETS.revenue_paise_per_store_month * sc.stores.length * scale * sc.factor,
      ),
      last_year: ly.revenue,
      trend: revSeries,
    },
    {
      key: "own_brand_share",
      unit: "ratio",
      value: cur.revenue ? Math.round((cur.own / cur.revenue) * 1000) / 1000 : null,
      target: TARGETS.own_brand_share,
      last_year: ly.revenue ? Math.round((ly.own / ly.revenue) * 1000) / 1000 : null,
      trend: shareSeries,
    },
    {
      key: "credit_outstanding",
      unit: "paise",
      value: lvl.outstanding,
      target: null,
      last_year: lvlLy.outstanding,
      trend: levelSeries((l) => l.outstanding),
    },
    {
      key: "credit_overdue",
      unit: "paise",
      value: lvl.overdue,
      target: Math.round(lvl.outstanding * 0.2),
      last_year: lvlLy.overdue,
      trend: levelSeries((l) => l.overdue),
    },
    {
      key: "verified_visits",
      unit: "count",
      value: verifiedVisits(sc, all),
      target: Math.round(TARGETS.verified_visits_per_officer_month * sc.officers.length * scale),
      last_year: verifiedVisits(sc, lyDays),
      trend: visitsSeries,
    },
    {
      key: "active_farmers",
      unit: "count",
      value: lvl.activeFarmers,
      target: Math.round(TARGETS.active_farmers_per_store * sc.stores.length * sc.factor),
      last_year: lvlLy.activeFarmers,
      trend: levelSeries((l) => l.activeFarmers),
    },
    {
      key: "open_flags",
      unit: "count",
      value: lvl.openFlags,
      target: 0,
      last_year: lvlLy.openFlags,
      trend: levelSeries((l) => l.openFlags),
    },
  ];
  const storeRevenue = sc.stores.map((s) => ({ s, rev: sales({ ...sc, stores: [s] }, all) }));
  const stores = storeRevenue.map(({ s, rev }) => {
    const target = TARGETS.revenue_paise_per_store_month * scale * sc.factor;
    const score = rev.revenue
      ? Math.min(100, Math.round((rev.revenue / Math.max(target, 1)) * 100))
      : null;
    return {
      id: s.id,
      code: s.code,
      name: s.name,
      district: s.district,
      cluster_id: s.cluster_id,
      lat: s.lat,
      lon: s.lon,
      revenue_paise: rev.revenue,
      own_brand_share: rev.revenue ? Math.round((rev.own / rev.revenue) * 1000) / 1000 : null,
      overdue_paise: storeLevels(s.id, sc.to).overdue,
      score,
      band: score === null ? "none" : score >= 80 ? "green" : score >= 50 ? "amber" : "red",
    };
  });
  const ranked = rankRows(sc.officers.map((o) => scorecard(o, sc, true)));
  const brief = (r: (typeof ranked)[number]) => ({
    id: r.officer_id,
    name: r.name,
    store_id: r.store_id,
    verified_visits: r.verified_visits,
    duty_days: r.duty_days,
    verified_visits_per_day: r.verified_visits_per_day,
  });
  const flagStores = new Set(sc.stores.map((s) => s.id));
  const flags = HIGH_FLAGS.filter((f) => flagStores.has(f.store_id)).map((f) => ({
    ...f,
    opened_at: istAt(addDays(sc.to, -f.age), 10, 15),
  }));
  return {
    filters: sc.echo,
    granularity: weekly ? "week" : "day",
    kpis,
    credit_overdue_buckets: lvl.buckets,
    series: { revenue: revSeries, revenue_last_year: lySeries, own_brand_share: shareSeries },
    stores,
    officers_top: ranked.slice(0, 5).map(brief),
    officers_bottom: [...ranked].reverse().slice(0, 5).map(brief),
    high_severity_flags: flags,
    crop_health_alerts: [],
    notes: { crop_health_alerts: "pending_an006" },
  };
}

const HIGH_FLAGS = [
  {
    id: "flag-101",
    rule: "VA-E02",
    severity: "high",
    title: "Visit far from the farm boundary",
    officer_id: "off-wgl-1",
    store_id: "store-wgl",
    farmer_id: "farmer-001",
    age: 1,
  },
  {
    id: "flag-102",
    rule: "VA-F06",
    severity: "high",
    title: "Registration burst: 11 farmers in 20 minutes",
    officer_id: "off-knr-1",
    store_id: "store-knr",
    farmer_id: null,
    age: 2,
  },
  {
    id: "flag-103",
    rule: "VA-F01",
    severity: "high",
    title: "Farmer phone matches a staff account",
    officer_id: "off-hbl-1",
    store_id: "store-hbl",
    farmer_id: "farmer-025",
    age: 3,
  },
  {
    id: "flag-104",
    rule: "VA-E01",
    severity: "high",
    title: "Mock location detected during duty",
    officer_id: "off-ngp-1",
    store_id: "store-ngp",
    farmer_id: null,
    age: 4,
  },
];

function fieldTeam(sc: Scope) {
  const locationVisible = sc.role !== "store_manager";
  return {
    filters: sc.echo,
    location_visible: locationVisible,
    items: rankRows(sc.officers.map((o) => scorecard(o, sc, locationVisible))),
  };
}

const PURPOSES = ["advisory", "follow_up", "collection", "demo"];

function officerProfile(o: Officer, sc: Scope) {
  const locationVisible = sc.role !== "store_manager";
  const store = MOCK_STORES.find((s) => s.id === o.store_id)!;
  const days = dayList(sc.from, sc.to).reverse();
  const dutyDays = days
    .map((d) => ({ d, x: officerDay(o.id, d) }))
    .filter((r) => r.x)
    .slice(0, 31)
    .map(({ d, x }) => ({
      day: d,
      start_at: istAt(d, 8, 30),
      end_at: d === todayIst() ? null : istAt(d, 17, 45),
      km: locationVisible ? x!.km : null,
      visits: x!.visits,
      verified_visits: x!.verified,
      time_on_farm_s: x!.timeOnFarm,
    }));
  const farmers = MOCK_FARMERS.filter((f) => f.store_id === o.store_id);
  const recent = dutyDays.flatMap((dd) =>
    Array.from({ length: Math.min(dd.visits, 3) }, (_, i) => {
      const f = farmers[(i + hash(dd.day)) % farmers.length]!;
      const score = Math.round(25 + rnd(`${o.id}:${dd.day}:${i}:score`) * 75);
      return {
        id: `visit-${o.id}-${dd.day}-${i}`,
        farmer_id: f.id,
        farmer_name: f.name,
        checkin_at: istAt(dd.day, 9 + i * 2, 10),
        checkout_at: istAt(dd.day, 9 + i * 2, 35),
        status: score >= 70 ? "verified" : score >= 40 ? "partial" : "unverified",
        score,
        purpose: pick(PURPOSES, `${dd.day}:${i}`),
      };
    }),
  );
  const card = scorecard(o, sc, locationVisible);
  const all = rankRows(
    sc.officers.length > 1 ? sc.officers.map((x) => scorecard(x, sc, locationVisible)) : [card],
  );
  card.rank = all.find((r) => r.officer_id === o.id)?.rank ?? 1;
  return {
    filters: sc.echo,
    id: o.id,
    name: o.name,
    phone: o.phone,
    status: "active",
    store_id: o.store_id,
    store_name: store.name,
    cluster_id: o.cluster_id,
    on_duty: !!officerDay(o.id, todayIst()),
    location_visible: locationVisible,
    scorecard: card,
    duty_days: dutyDays,
    recent_visits: recent.slice(0, 20),
  };
}

/**
 * One hand-shaped day for any officer and date: duty 08:30-17:30 IST, a point every 5 minutes
 * along a loop through four farms, a 90-minute gap (no reason, VV-008 pending) and a 40-minute
 * gap with a reason, one stop, visits verified / partial / unverified / verified.
 */
export function dayReplay(o: Officer, date: string, sc: Scope) {
  const store = MOCK_STORES.find((s) => s.id === o.store_id)!;
  const empty = {
    filters: sc.echo,
    officer_id: o.id,
    officer_name: o.name,
    date,
    duty_sessions: [],
    km: 0,
    track: { type: "MultiLineString", coordinates: [] },
    points: [],
    stops: [],
    gaps: [],
    visits: [],
    timeline: [],
  };
  if (date > todayIst() || weekday(date) === 0) return empty;
  const farmers = MOCK_FARMERS.filter((f) => f.store_id === o.store_id);
  const stopsAt = [0, 1, 2, 0].map((i, k) => {
    const f = farmers[i % farmers.length]!;
    return { f, lat: f.lat + k * 0.004, lon: f.lon - k * 0.003 };
  });
  // Waypoints (IST minutes from midnight): store -> farm1 -> farm2 -> (gap) -> farm3 -> farm4 -> store
  const way: Array<[number, number, number]> = [
    [510, store.lat, store.lon],
    [560, stopsAt[0]!.lat, stopsAt[0]!.lon],
    [600, stopsAt[0]!.lat, stopsAt[0]!.lon],
    [650, stopsAt[1]!.lat, stopsAt[1]!.lon],
    [690, stopsAt[1]!.lat, stopsAt[1]!.lon],
    [720, (stopsAt[1]!.lat + stopsAt[2]!.lat) / 2, (stopsAt[1]!.lon + stopsAt[2]!.lon) / 2],
    [810, (stopsAt[1]!.lat + stopsAt[2]!.lat) / 2 + 0.01, (stopsAt[1]!.lon + stopsAt[2]!.lon) / 2],
    [850, stopsAt[2]!.lat, stopsAt[2]!.lon],
    [880, stopsAt[2]!.lat, stopsAt[2]!.lon],
    [920, stopsAt[3]!.lat, stopsAt[3]!.lon],
    [945, stopsAt[3]!.lat, stopsAt[3]!.lon],
    [1050, store.lat + 0.002, store.lon + 0.002],
  ];
  const gapsMin: Array<[number, number, string | null]> = [
    [720, 810, null],
    [960, 1000, "Phone battery died"],
  ];
  const points: Array<{ ts: string; lat: number; lon: number; accuracy_m: number }> = [];
  const segments: number[][][] = [[]];
  for (let m = 510; m <= 1050; m += 5) {
    const gap = gapsMin.find(([s, e]) => m > s && m < e);
    if (gap) {
      if (segments[segments.length - 1]!.length) segments.push([]);
      continue;
    }
    const i = way.findIndex((w) => w[0] >= m);
    const b = way[Math.max(0, i)]!;
    const a = way[Math.max(0, i - 1)]!;
    const f = b[0] === a[0] ? 0 : (m - a[0]) / (b[0] - a[0]);
    const jitter = (rnd(`${o.id}:${date}:${m}`) - 0.5) * 0.0008;
    const lat = Math.round((a[1] + (b[1] - a[1]) * f + jitter) * 1e6) / 1e6;
    const lon = Math.round((a[2] + (b[2] - a[2]) * f - jitter) * 1e6) / 1e6;
    const hh = Math.floor(m / 60);
    points.push({
      ts: istAt(date, hh, m % 60),
      lat,
      lon,
      accuracy_m: 8 + Math.round(rnd(`${m}:acc`) * 20),
    });
    segments[segments.length - 1]!.push([lon, lat]);
  }
  const statuses: Array<
    ["verified" | "partial" | "unverified", "green" | "amber" | "red", number]
  > = [
    ["verified", "green", 90],
    ["partial", "amber", 55],
    ["unverified", "red", 25],
    ["verified", "green", 80],
  ];
  const visitWindows: Array<[number, number]> = [
    [562, 598],
    [652, 688],
    [852, 878],
    [922, 944],
  ];
  const visits = stopsAt.map((s, k) => {
    const [status, colour, score] = statuses[k]!;
    const [ci, co] = visitWindows[k]!;
    const comp =
      status === "verified"
        ? { geofence: 30, confirmation: 30, photo: k === 0 ? 20 : 0, duration: 10, integrity: 10 }
        : status === "partial"
          ? { geofence: 30, confirmation: 0, photo: 0, duration: 15, integrity: 10 }
          : { geofence: 0, confirmation: 0, photo: 0, duration: 15, integrity: 10 };
    const max = { geofence: 30, confirmation: 30, photo: 20, duration: 10, integrity: 10 };
    return {
      id: `visit-${o.id}-${date}-${k}`,
      farmer_id: s.f.id,
      farmer_name: s.f.name,
      purpose: PURPOSES[k % PURPOSES.length]!,
      checkin_at: istAt(date, Math.floor(ci / 60), ci % 60),
      checkout_at: istAt(date, Math.floor(co / 60), co % 60),
      duration_s: (co - ci) * 60,
      lat: s.lat,
      lon: s.lon,
      geofence_result: comp.geofence ? "inside" : "outside",
      status,
      colour,
      score,
      score_components: comp,
      proof: (["geofence", "photo", "confirmation", "duration", "integrity"] as const).map(
        (kind) => ({
          kind,
          satisfied: comp[kind] > 0,
          points: comp[kind],
          max_points: max[kind],
        }),
      ),
      confirmed_at: comp.confirmation ? istAt(date, Math.floor(co / 60), co % 60) : null,
      photos: comp.photo ? 2 : 0,
    };
  });
  const session = {
    id: `duty-${o.id}-${date}`,
    start_at: istAt(date, 8, 30),
    end_at: istAt(date, 17, 30),
    end_reason: "manual",
    km: 38.4,
  };
  const gaps = gapsMin.map(([s, e, reason]) => ({
    start: istAt(date, Math.floor(s / 60), s % 60),
    end: istAt(date, Math.floor(e / 60), e % 60),
    duration_s: (e - s) * 60,
    duty_session_id: session.id,
    reason,
  }));
  const stop = {
    lat: stopsAt[1]!.lat,
    lon: stopsAt[1]!.lon,
    start: istAt(date, 10, 50),
    end: istAt(date, 11, 30),
    duration_s: 2400,
  };
  const timeline = [
    { ts: session.start_at, type: "duty_start", ref_id: session.id, detail: {} },
    ...visits.flatMap((v) => [
      {
        ts: v.checkin_at,
        type: "visit_checkin",
        ref_id: v.id,
        detail: { farmer_name: v.farmer_name, status: v.status, score: v.score },
      },
      {
        ts: v.checkout_at,
        type: "visit_checkout",
        ref_id: v.id,
        detail: { farmer_name: v.farmer_name, duration_s: v.duration_s },
      },
    ]),
    { ts: stop.start, type: "stop", ref_id: null, detail: { duration_s: stop.duration_s } },
    ...gaps.flatMap((g) => [
      {
        ts: g.start,
        type: "gap_start",
        ref_id: null,
        detail: { duration_s: g.duration_s, reason: g.reason },
      },
      {
        ts: g.end,
        type: "gap_end",
        ref_id: null,
        detail: { duration_s: g.duration_s, reason: g.reason },
      },
    ]),
    { ts: session.end_at, type: "duty_end", ref_id: session.id, detail: { end_reason: "manual" } },
  ].sort((a, b) => a.ts.localeCompare(b.ts));
  return {
    ...empty,
    duty_sessions: [session],
    km: session.km,
    track: { type: "MultiLineString", coordinates: segments.filter((s) => s.length > 1) },
    points,
    stops: [stop],
    gaps,
    visits,
    timeline,
  };
}

// ---- farmers --------------------------------------------------------------------------------
function farmerFacts(f: Farmer, to: string) {
  const lastVisitDaysAgo = rnd(`${f.id}:lv`) < 0.12 ? null : Math.floor(rnd(`${f.id}:lvd`) * 150);
  const lastPurchaseDaysAgo = rnd(`${f.id}:lp`) < 0.1 ? null : Math.floor(rnd(`${f.id}:lpd`) * 120);
  const balance = Math.round(rnd(`${f.id}:bal`) * 40_000) * 100;
  const riskRoll = rnd(`${f.id}:risk`);
  const overdue = riskRoll < 0.45 ? 0 : Math.round(balance * (0.3 + riskRoll * 0.5));
  const risk = overdue === 0 ? "low" : riskRoll > 0.8 ? "high" : "medium";
  return {
    last_visit_at: lastVisitDaysAgo === null ? null : istAt(addDays(to, -lastVisitDaysAgo), 11, 5),
    lastVisitDaysAgo,
    last_purchase_at:
      lastPurchaseDaysAgo === null ? null : istAt(addDays(to, -lastPurchaseDaysAgo), 16, 40),
    balance,
    overdue,
    risk: risk as "low" | "medium" | "high",
    ltv: Math.round(2_000 + rnd(`${f.id}:ltv`) * 60_000) * 100,
    app_user: rnd(`${f.id}:app`) > 0.4,
    consent_marketing: rnd(`${f.id}:mkt`) > 0.35,
  };
}

function farmerRow(f: Farmer, to: string) {
  const x = farmerFacts(f, to);
  return {
    id: f.id,
    name: f.name,
    phone_masked: `*********${f.phone.slice(-4)}`,
    village_id: f.village_id,
    village: f.village,
    district: f.district,
    store_id: f.store_id,
    registered_by: f.registered_by,
    crops: f.crop_ids.map((c) => c.replace("crop-", "")),
    stages: [f.stage],
    acres: f.acres,
    last_visit_at: x.last_visit_at,
    last_purchase_at: x.last_purchase_at,
    balance_paise: x.balance,
    overdue_paise: x.overdue,
    credit_risk: x.risk,
    ltv_paise: x.ltv,
    app_user: x.app_user,
    consent_marketing: x.consent_marketing,
  };
}

function farmersInScope(sc: Scope, q: URLSearchParams): Farmer[] {
  const storeIds = new Set(sc.stores.map((s) => s.id));
  let list = MOCK_FARMERS.filter((f) => storeIds.has(f.store_id));
  if (sc.role === "field_officer" || q.get("officer_id"))
    list = list.filter((f) => sc.officers.some((o) => o.id === f.registered_by));
  const crop = q.get("crop_id");
  if (crop) list = list.filter((f) => f.crop_ids.includes(crop));
  return list;
}

const FARMER_SORTS = ["name", "last_visit", "last_purchase", "ltv", "balance", "overdue"];

function farmersDirectory(sc: Scope, q: URLSearchParams): MockResult {
  const sortRaw = q.get("sort") ?? "name";
  const desc = sortRaw.startsWith("-");
  const sortKey = desc ? sortRaw.slice(1) : sortRaw;
  if (!FARMER_SORTS.includes(sortKey)) return problem(422, "invalid_sort", "Unknown sort.");
  const limit = Math.min(200, Math.max(1, Number(q.get("limit") ?? 50) || 50));
  const cursor = q.get("cursor");
  let offset = 0;
  if (cursor) {
    const m = /^o(\d+)$/.exec(cursor);
    if (!m) return problem(400, "invalid_cursor", "Bad cursor.");
    offset = Number(m[1]);
  }
  const term = (q.get("q") ?? "").trim().toLowerCase();
  const district = q.get("district");
  const stage = q.get("stage");
  const risk = q.get("credit_risk");
  const lastVisit = q.get("last_visit");
  let rows = farmersInScope(sc, q).map((f) => ({
    f,
    row: farmerRow(f, sc.to),
    facts: farmerFacts(f, sc.to),
  }));
  if (term)
    rows = rows.filter(
      ({ f }) =>
        f.name.toLowerCase().includes(term) ||
        f.village.toLowerCase().includes(term) ||
        (/^\d{4}$/.test(term) && f.phone.endsWith(term)),
    );
  if (district) rows = rows.filter(({ f }) => f.district === district);
  if (stage) rows = rows.filter(({ f }) => f.stage === stage);
  if (risk) rows = rows.filter(({ row }) => row.credit_risk === risk);
  if (lastVisit) {
    const d = (r: (typeof rows)[number]) => r.facts.lastVisitDaysAgo;
    rows = rows.filter((r) => {
      const v = d(r);
      if (lastVisit === "never") return v === null;
      if (lastVisit === "over_90d") return v === null || v > 90;
      const n = Number(lastVisit.replace("d", ""));
      return v !== null && v <= n;
    });
  }
  const value = (r: (typeof rows)[number]): string | number | null => {
    switch (sortKey) {
      case "last_visit":
        return r.row.last_visit_at;
      case "last_purchase":
        return r.row.last_purchase_at;
      case "ltv":
        return r.row.ltv_paise;
      case "balance":
        return r.row.balance_paise;
      case "overdue":
        return r.row.overdue_paise;
      default:
        return r.row.name;
    }
  };
  rows.sort((a, b) => {
    const va = value(a);
    const vb = value(b);
    if (va === null && vb === null) return a.row.name.localeCompare(b.row.name);
    if (va === null) return 1;
    if (vb === null) return -1;
    const c =
      typeof va === "number" && typeof vb === "number"
        ? va - vb
        : String(va).localeCompare(String(vb));
    return (desc ? -c : c) || a.row.id.localeCompare(b.row.id);
  });
  const page = rows.slice(offset, offset + limit).map((r) => r.row);
  return ok({
    filters: sc.echo,
    total: rows.length,
    next_cursor: offset + limit < rows.length ? `o${offset + limit}` : null,
    items: page,
  });
}

function square(lat: number, lon: number, size: number) {
  return [
    [
      [lon - size, lat - size],
      [lon + size, lat - size * 0.8],
      [lon + size * 1.1, lat + size],
      [lon - size * 0.9, lat + size * 1.1],
      [lon - size, lat - size],
    ],
  ];
}

function farmer360(f: Farmer, sc: Scope) {
  const x = farmerFacts(f, sc.to);
  const officer = MOCK_OFFICERS.find((o) => o.id === f.registered_by)!;
  const farms = f.crop_ids.map((cropId, i) => {
    const lat = f.lat + i * 0.006;
    const lon = f.lon + i * 0.005;
    const area = Math.round((f.acres / f.crop_ids.length) * 10) / 10;
    return {
      id: `farm-${f.id}-${i}`,
      name: i === 0 ? "Home field" : "River plot",
      survey_no: `${100 + (hash(f.id) % 300)}/${i + 1}`,
      area_acres: area,
      area_acres_computed: Math.round(area * 1.04 * 10) / 10,
      soil: pick(["black", "red", "loamy"], `${f.id}:${i}:soil`),
      irrigation: pick(["borewell", "canal", "rainfed"], `${f.id}:${i}:irr`),
      boundary: { type: "Polygon", coordinates: square(lat, lon, 0.0015) },
      centroid: { type: "Point", coordinates: [lon, lat] },
      crop_plots: [
        {
          id: `plot-${f.id}-${i}`,
          crop_id: cropId,
          crop_code: cropId.replace("crop-", ""),
          crop_name: CROP_NAMES[cropId] ?? cropId,
          variety: pick(
            ["BPT 5204", "RNR 15048", "Bt hybrid", "Teja", "Local"],
            `${f.id}:${i}:var`,
          ),
          season: "kharif",
          sowing_date: addDays(sc.to, -(60 + (hash(`${f.id}:${i}`) % 40))),
          stage: i === 0 ? f.stage : "vegetative",
          expected_harvest: addDays(sc.to, 40 + (hash(`${f.id}:${i}:h`) % 30)),
          area_acres: area,
        },
      ],
    };
  });
  const visits = Array.from({ length: 6 }, (_, i) => {
    const day = addDays(sc.to, -(i * 9 + 2));
    const score = Math.round(30 + rnd(`${f.id}:v${i}`) * 70);
    return {
      id: `visit-${f.id}-${i}`,
      officer_id: officer.id,
      officer_name: officer.name,
      purpose: pick(PURPOSES, `${f.id}:${i}:p`),
      checkin_at: istAt(day, 10, 20),
      checkout_at: istAt(day, 10, 48),
      status: score >= 70 ? "verified" : score >= 40 ? "partial" : "unverified",
      score,
      confirmed: score >= 70,
      crop_stage: f.stage,
    };
  });
  const orders = Array.from({ length: 5 }, (_, i) => {
    const day = addDays(sc.to, -(i * 11 + 4));
    return {
      id: `order-${f.id}-${i}`,
      store_id: f.store_id,
      channel: pick(["pos", "field", "app"], `${f.id}:${i}:ch`),
      status: i === 0 ? "confirmed" : "delivered",
      total_paise: Math.round(800 + rnd(`${f.id}:o${i}`) * 9_000) * 100,
      placed_at: istAt(day, 15, 10),
      invoice_no: i === 0 ? null : `INV-${f.store_id.slice(6).toUpperCase()}-${2400 + i}`,
      lines: 1 + (hash(`${f.id}:${i}:l`) % 4),
    };
  });
  const b = x.overdue;
  return {
    filters: sc.echo,
    profile: {
      id: f.id,
      name: f.name,
      phone: f.phone,
      phone_verified: true,
      language: pick(["te", "kn", "mr", "hi"], f.district),
      landmark: "Near the panchayat office",
      source: "field",
      village_id: f.village_id,
      village: f.village,
      district: f.district,
      store_id: f.store_id,
      registered_by: officer.id,
      registered_by_name: officer.name,
      created_at: istAt(addDays(sc.to, -200), 12, 0),
      updated_at: istAt(addDays(sc.to, -3), 12, 0),
    },
    farms,
    visits,
    diagnoses: [],
    orders,
    khata: {
      balance_paise: x.balance,
      overdue_paise: b,
      overdue_buckets: {
        "0_30": Math.round(b * 0.4),
        "31_60": Math.round(b * 0.3),
        "61_90": Math.round(b * 0.2),
        "90_plus": b - Math.round(b * 0.4) - Math.round(b * 0.3) - Math.round(b * 0.2),
      },
      next_due_date: x.balance ? addDays(sc.to, 12) : null,
      credit_limits: [{ store_id: f.store_id, limit_paise: 50_000_00 }],
      last_payment_at: istAt(addDays(sc.to, -18), 13, 30),
      credit_risk: x.risk,
    },
    consent: {
      current: { data: true, marketing: x.consent_marketing },
      history: [
        {
          purpose: "data",
          granted: true,
          at: istAt(addDays(sc.to, -200), 12, 0),
          version: "2026-06",
          channel: "field",
        },
        {
          purpose: "marketing",
          granted: true,
          at: istAt(addDays(sc.to, -200), 12, 0),
          version: "2026-06",
          channel: "field",
        },
        ...(x.consent_marketing
          ? []
          : [
              {
                purpose: "marketing",
                granted: false,
                at: istAt(addDays(sc.to, -40), 9, 0),
                version: "2026-06",
                channel: "app",
              },
            ]),
      ],
    },
    app_usage: {
      has_app_login: x.app_user,
      last_session_at: x.app_user ? istAt(addDays(sc.to, -2), 19, 0) : null,
      sessions_last_60_days: x.app_user ? 4 + (hash(`${f.id}:s`) % 20) : 0,
      proxy: "refresh_token_issuance",
    },
    ltv_paise: x.ltv,
    last_visit_at: visits[0]!.checkin_at,
    last_purchase_at: orders[0]!.placed_at,
    active: true,
    notes: { diagnoses: "pending_m6_diagnosis" },
  };
}

// ---- stores ---------------------------------------------------------------------------------
function storeFigures(s: Store, sc: Scope, days: string[]) {
  const sale = sales({ ...sc, stores: [s] }, days);
  const cogs = Math.round(sale.revenue * (0.72 + rnd(`${s.id}:cogs`) * 0.1));
  const margin = sale.revenue - cogs;
  return { sale, cogs, margin };
}

function storeRow(s: Store, sc: Scope) {
  const { sale, cogs, margin } = storeFigures(s, sc, dayList(sc.from, sc.to));
  const lvl = storeLevels(s.id, sc.to);
  const lastClose = addDays(sc.to, weekday(sc.to) === 0 ? -1 : 0);
  return {
    id: s.id,
    code: s.code,
    name: s.name,
    district: s.district,
    cluster_id: s.cluster_id,
    net_sales_paise: sale.revenue,
    cogs_paise: cogs,
    gross_margin_paise: margin,
    gross_margin_pct: sale.revenue ? Math.round((margin / sale.revenue) * 1000) / 1000 : null,
    own_brand_share: sale.revenue ? Math.round((sale.own / sale.revenue) * 1000) / 1000 : null,
    orders: Math.round(sale.revenue / 1_800_00),
    stock_value_paise: Math.round((8_00_000 + rnd(`${s.id}:stock`) * 20_00_000) * 100),
    credit_outstanding_paise: lvl.outstanding,
    credit_overdue_paise: lvl.overdue,
    last_day_close: {
      business_date: lastClose,
      variance_paise: Math.round((rnd(`${s.id}:${lastClose}:var`) - 0.5) * 1_200) * 100,
      status: "closed",
    },
  };
}

const CATEGORIES = ["seed", "fertiliser", "pesticide", "fungicide", "herbicide", "growth", "tool"];

function storeDetail(s: Store, sc: Scope) {
  const row = storeRow(s, sc);
  const weights = CATEGORIES.map((c) => 0.3 + rnd(`${s.id}:${c}`));
  const wsum = weights.reduce((a, b) => a + b, 0);
  const salesByCategory = CATEGORIES.map((category, i) => {
    const net = Math.round((row.net_sales_paise * weights[i]!) / wsum);
    return {
      category,
      net_sales_paise: net,
      gross_margin_paise: Math.round(net * (0.12 + rnd(`${s.id}:${category}:m`) * 0.18)),
      share: row.net_sales_paise ? Math.round((net / row.net_sales_paise) * 1000) / 1000 : null,
    };
  }).sort((a, b) => b.net_sales_paise - a.net_sales_paise);
  const own = Math.round(row.net_sales_paise * (row.own_brand_share ?? 0));
  const lvl = storeLevels(s.id, sc.to);
  const dayCloses = dayList(sc.from, sc.to)
    .reverse()
    .filter((d) => weekday(d) !== 0)
    .slice(0, 30)
    .map((d) => {
      const expected = storeDay(s.id, d).revenue * 0.45;
      const variance = Math.round((rnd(`${s.id}:${d}:var`) - 0.5) * 1_600) * 100;
      return {
        business_date: d,
        cash_expected_paise: Math.round(expected),
        cash_counted_paise: Math.round(expected + variance),
        variance_paise: variance,
        status: "closed",
        variance_flagged: Math.abs(variance) > 500_00,
      };
    });
  // P&L by month over the range; months cut by the range are partial.
  const months: string[] = [];
  for (let m = sc.from.slice(0, 7); m <= sc.to.slice(0, 7); ) {
    months.push(m);
    const [y, mm] = m.split("-").map(Number) as [number, number];
    m = mm === 12 ? `${y + 1}-01` : `${y}-${String(mm + 1).padStart(2, "0")}`;
  }
  const pnl = months.map((month) => {
    const first = `${month}-01`;
    const [y, mm] = month.split("-").map(Number) as [number, number];
    const lastDay = new Date(Date.UTC(y, mm, 0)).toISOString().slice(0, 10);
    const from = first < sc.from ? sc.from : first;
    const to = lastDay > sc.to ? sc.to : lastDay;
    const { sale, cogs } = storeFigures(s, sc, dayList(from, to));
    const discounts = Math.round(sale.revenue * 0.03);
    const gross = sale.revenue + discounts;
    const marginM = sale.revenue - cogs;
    const writeOffs = Math.round(sale.revenue * (0.002 + rnd(`${s.id}:${month}:wo`) * 0.006));
    return {
      month,
      partial: from !== first || to !== lastDay,
      gross_sales_paise: gross,
      discounts_paise: discounts,
      net_sales_paise: sale.revenue,
      cogs_paise: cogs,
      gross_margin_paise: marginM,
      gross_margin_pct: sale.revenue ? Math.round((marginM / sale.revenue) * 1000) / 1000 : null,
      write_offs_paise: writeOffs,
      contribution_paise: marginM - writeOffs,
    };
  });
  const turns = row.stock_value_paise
    ? Math.round((row.cogs_paise / row.stock_value_paise) * 100) / 100
    : null;
  return {
    filters: sc.echo,
    id: s.id,
    code: s.code,
    name: s.name,
    district: s.district,
    cluster_id: s.cluster_id,
    net_sales_paise: row.net_sales_paise,
    cogs_paise: row.cogs_paise,
    gross_margin_paise: row.gross_margin_paise,
    gross_margin_pct: row.gross_margin_pct,
    sales_by_category: salesByCategory,
    brand_split: {
      own_brand_paise: own,
      multi_brand_paise: row.net_sales_paise - own,
      own_brand_share: row.own_brand_share,
      own_brand_margin_paise: Math.round(own * 0.28),
      multi_brand_margin_paise: Math.round((row.net_sales_paise - own) * 0.14),
    },
    stock: {
      value_paise: row.stock_value_paise,
      skus_in_stock: 80 + (hash(s.id) % 60),
      turns,
      turns_annualised: turns === null ? null : Math.round(((turns * 365) / sc.days) * 10) / 10,
      stockouts: [
        { sku_id: "sku-imida-100", product_name: "FCC Imida", pack: "100 ml" },
        { sku_id: "sku-urea-45", product_name: "Neem-coated urea", pack: "45 kg" },
      ].slice(0, 1 + (hash(s.id) % 2)),
    },
    credit_book: {
      outstanding_paise: lvl.outstanding,
      overdue_paise: lvl.overdue,
      buckets: lvl.buckets,
      accounts: 60 + (hash(`${s.id}:acc`) % 120),
    },
    day_closes: dayCloses,
    pnl,
    pnl_opex_included: false,
    pnl_note: "operating_expenses_out_of_scope",
  };
}

// ---- router ---------------------------------------------------------------------------------
/** `/v1/analytics/*` of the mock API; null when the path is not an analytics route. */
export function handleAnalytics(
  method: string,
  path: string[],
  query: URLSearchParams,
  actor: MockActor | null,
): MockResult | null {
  if (path[0] !== "analytics") return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  if (method !== "GET") return problem(405, "method_not_allowed", "Read-only.");
  const role = actor.role;
  const [, a, id, c] = path;
  const gate = (roles: readonly string[], fn: (sc: Scope) => MockResult): MockResult => {
    if (!roles.includes(role)) return problem(403, "forbidden", "Your role cannot read this view.");
    const sc = resolveScope(role, query);
    return "status" in sc ? sc : fn(sc);
  };
  const officerInScope = (sc: Scope, officerId: string) => {
    // The path names the officer; only the role scope applies (query officer_id is ignored).
    const scoped = resolveScope(role, new URLSearchParams({ from: sc.from, to: sc.to }));
    if ("status" in scoped) return undefined;
    return scoped.officers.find((o) => o.id === officerId);
  };

  if (a === "owner-home" && !id) return gate(HOME_ROLES, (sc) => ok(ownerHome(sc)));
  if (a === "field-team" && !id) return gate(TEAM_ROLES, (sc) => ok(fieldTeam(sc)));
  if (a === "officers" && id && !c)
    return gate(TEAM_ROLES, (sc) => {
      const o = officerInScope(sc, id);
      return o ? ok(officerProfile(o, sc)) : problem(404, "not_found", "Officer not found.");
    });
  if (a === "officers" && id && c === "day-replay")
    return gate(REPLAY_ROLES, (sc) => {
      const date = query.get("date");
      if (!isDate(date)) return problem(422, "validation_error", "date is required (YYYY-MM-DD).");
      const o = officerInScope(sc, id);
      return o ? ok(dayReplay(o, date, sc)) : problem(404, "not_found", "Officer not found.");
    });
  if (a === "farmers" && !id) return gate(FARMER_ROLES, (sc) => farmersDirectory(sc, query));
  if (a === "farmers" && id && c === "360")
    return gate(FARMER_ROLES, (sc) => {
      const scoped = resolveScope(role, new URLSearchParams({ from: sc.from, to: sc.to }));
      if ("status" in scoped) return scoped;
      const f = farmersInScope(scoped, new URLSearchParams()).find((x) => x.id === id);
      return f ? ok(farmer360(f, sc)) : problem(404, "not_found", "Farmer not found.");
    });
  if (a === "stores" && !id)
    return gate(STORE_ROLES, (sc) =>
      ok({ filters: sc.echo, items: sc.stores.map((s) => storeRow(s, sc)) }),
    );
  if (a === "stores" && id && !c)
    return gate(STORE_ROLES, (sc) => {
      const scoped = resolveScope(role, new URLSearchParams({ from: sc.from, to: sc.to }));
      if ("status" in scoped) return scoped;
      const s = scoped.stores.find((x) => x.id === id);
      return s
        ? ok(storeDetail(s, { ...sc, stores: [s] }))
        : problem(404, "not_found", "Store not found.");
    });
  return problem(404, "not_found", `No mock for ${method} /analytics/${path.slice(1).join("/")}`);
}
