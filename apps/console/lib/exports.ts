/**
 * WC-013 exports and scheduled reports (C100). Typed `/v1/exports*` and `/v1/report-schedules*`
 * calls plus `describeCron()` / `cronSummary()`, which turn the stored cron expression into the
 * human-readable line the screen shows. Schedules are stored and shown in **IST** (the API's
 * `report_schedule.cron` is evaluated in Asia/Kolkata), so every summary says so.
 *
 * `POST /v1/exports` and writing a schedule need step-up (SEC-028): callers pass the headers
 * from `useStepUp().run(...)`.
 */
import { authedFetch } from "./api";
import type { MessageKey, TFunction } from "./i18n";

export const EXPORT_FORMATS = ["csv", "xlsx", "xml"] as const;
export type ExportFormat = (typeof EXPORT_FORMATS)[number];

/** Every staff role may open C100; the API checks the resource's own roles per call. */
export const EXPORT_ROLES: ReadonlyArray<string> = [
  "owner",
  "director",
  "tenant_admin",
  "auditor",
  "accountant",
  "cluster_head",
  "store_manager",
  "field_officer",
  "agronomist",
];
/** Roles that may create and edit scheduled reports (`x-roles` of createReportSchedule). */
export const SCHEDULE_ROLES: ReadonlyArray<string> = [
  "owner",
  "director",
  "tenant_admin",
  "auditor",
  "accountant",
  "cluster_head",
  "store_manager",
];

export interface ExportResource {
  name: string;
  formats: ExportFormat[];
  columns: string[];
  filters: string[];
  description: string;
}

export interface ExportJob {
  id: string;
  resource: string;
  format: ExportFormat | string;
  filters: Record<string, unknown>;
  status: string;
  rows: number;
  size_bytes: number;
  filename: string;
  url: string | null;
  url_expires_at: string | null;
  created_at: string;
  created_by?: string | null;
}

export interface ReportSchedule {
  id: string;
  name: string;
  resource: string;
  format: ExportFormat | string;
  filters: Record<string, unknown>;
  recipients: string[];
  /** Cron expression evaluated in Asia/Kolkata. */
  cron: string;
  active: boolean;
  last_run_at: string | null;
  next_run_at: string | null;
  created_at: string;
}

export interface ScheduleInput {
  name: string;
  resource: string;
  format: ExportFormat;
  filters: Record<string, unknown>;
  recipients: string[];
  cron: string;
  active: boolean;
}

export const exportsApi = {
  resources: () => authedFetch<{ items: ExportResource[] }>("v1/exports/resources"),
  run: (
    body: { resource: string; filters: Record<string, unknown>; format: ExportFormat },
    headers: Record<string, string> = {},
  ) => authedFetch<ExportJob>("v1/exports", { body, headers }),
  list: () => authedFetch<{ items: ExportJob[] }>("v1/exports"),
  get: (id: string) => authedFetch<ExportJob>(`v1/exports/${id}`),
  schedules: () => authedFetch<{ items: ReportSchedule[] }>("v1/report-schedules"),
  createSchedule: (body: ScheduleInput, headers: Record<string, string> = {}) =>
    authedFetch<ReportSchedule>("v1/report-schedules", { body, headers }),
  patchSchedule: (id: string, body: Partial<ScheduleInput>, headers: Record<string, string> = {}) =>
    authedFetch<ReportSchedule>(`v1/report-schedules/${id}`, { method: "PATCH", body, headers }),
  deleteSchedule: (id: string, headers: Record<string, string> = {}) =>
    authedFetch<void>(`v1/report-schedules/${id}`, { method: "DELETE", headers }),
};

// ---- cron (pure, unit-tested) ---------------------------------------------------------------

export const DEFAULT_CRON = "0 8 * * 1";

export const CRON_DAY_KEYS = [
  "sunday",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
] as const;
export type CronDayKey = (typeof CRON_DAY_KEYS)[number];

export interface CronDescription {
  minute: number;
  hour: number;
  /** `daily`, `weekly` (one or more week days), `monthly` (a day of the month) or `custom`. */
  kind: "daily" | "weekly" | "monthly" | "custom";
  days: CronDayKey[];
  dayOfMonth: number | null;
  /** `08:00`, always IST. */
  time: string;
}

const RANGE = (spec: string, min: number, max: number): number[] | null => {
  const out = new Set<number>();
  for (const part of spec.split(",")) {
    if (part === "*") {
      for (let i = min; i <= max; i++) out.add(i);
      continue;
    }
    const step = part.split("/");
    if (step.length > 2) return null;
    const stride = step.length === 2 ? Number(step[1]) : 1;
    if (!Number.isInteger(stride) || stride < 1) return null;
    const base = step[0]!;
    let lo: number;
    let hi: number;
    if (base === "*") {
      lo = min;
      hi = max;
    } else if (base.includes("-")) {
      const [a, b] = base.split("-");
      lo = Number(a);
      hi = Number(b);
    } else {
      lo = Number(base);
      hi = lo;
    }
    if (!Number.isInteger(lo) || !Number.isInteger(hi) || lo < min || hi > max || hi < lo)
      return null;
    for (let i = lo; i <= hi; i += stride) out.add(i);
  }
  return [...out].sort((a, b) => a - b);
};

/** Parse a 5-field cron expression; null when it is not one we can describe. */
export function describeCron(cron: string): CronDescription | null {
  const fields = cron.trim().split(/\s+/);
  if (fields.length !== 5) return null;
  const [minF, hourF, domF, monF, dowF] = fields as [string, string, string, string, string];
  const minutes = RANGE(minF, 0, 59);
  const hours = RANGE(hourF, 0, 23);
  if (!minutes || !hours || minutes.length !== 1 || hours.length !== 1) return null;
  const minute = minutes[0]!;
  const hour = hours[0]!;
  const time = `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
  const base = { minute, hour, time };

  if (monF !== "*") return { ...base, kind: "custom", days: [], dayOfMonth: null };
  if (dowF === "*" && domF === "*") return { ...base, kind: "daily", days: [], dayOfMonth: null };
  if (dowF === "*") {
    const dom = RANGE(domF, 1, 31);
    if (!dom) return null;
    if (dom.length !== 1) return { ...base, kind: "custom", days: [], dayOfMonth: null };
    return { ...base, kind: "monthly", days: [], dayOfMonth: dom[0]! };
  }
  const dows = RANGE(dowF.replace(/7/g, "0"), 0, 6);
  if (!dows || dows.length === 0) return null;
  if (domF !== "*") return { ...base, kind: "custom", days: [], dayOfMonth: null };
  if (dows.length === 7) return { ...base, kind: "daily", days: [], dayOfMonth: null };
  return {
    ...base,
    kind: "weekly",
    days: dows.map((d) => CRON_DAY_KEYS[d]!),
    dayOfMonth: null,
  };
}

export function isValidCron(cron: string): boolean {
  return describeCron(cron) !== null;
}

/**
 * "Every Monday at 08:00 IST". An expression we cannot describe is shown verbatim with the
 * time zone, so a schedule created through the API is never silently mis-described.
 */
export function cronSummary(cron: string, t: TFunction): string {
  const d = describeCron(cron);
  if (!d) return t("reports.cron.custom", { cron });
  switch (d.kind) {
    case "daily":
      return t("reports.cron.daily", { time: d.time });
    case "monthly":
      return t("reports.cron.monthly", { day: d.dayOfMonth ?? 1, time: d.time });
    case "weekly": {
      const days = d.days.map((k) => t(`reports.cron.day.${k}` as MessageKey)).join(", ");
      return t("reports.cron.weekly", { days, time: d.time });
    }
    default:
      return t("reports.cron.custom", { cron });
  }
}

/** Presets offered by the schedule editor (the API default is Monday 08:00 IST). */
export const CRON_PRESETS: ReadonlyArray<{ cron: string; labelKey: MessageKey }> = [
  { cron: "0 8 * * 1", labelKey: "reports.preset.weekly" },
  { cron: "0 8 * * *", labelKey: "reports.preset.daily" },
  { cron: "0 8 1 * *", labelKey: "reports.preset.monthly" },
];

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export interface ScheduleIssue {
  field: "name" | "recipients" | "cron" | "resource";
  code: string;
}

export function validateSchedule(input: {
  name: string;
  resource: string;
  recipients: string[];
  cron: string;
}): ScheduleIssue[] {
  const issues: ScheduleIssue[] = [];
  if (input.name.trim().length < 3) issues.push({ field: "name", code: "nameTooShort" });
  if (!input.resource) issues.push({ field: "resource", code: "resourceRequired" });
  if (input.recipients.length === 0)
    issues.push({ field: "recipients", code: "recipientsRequired" });
  else if (!input.recipients.every((r) => EMAIL.test(r)))
    issues.push({ field: "recipients", code: "recipientInvalid" });
  if (!isValidCron(input.cron)) issues.push({ field: "cron", code: "cronInvalid" });
  return issues;
}

export function parseRecipients(raw: string): string[] {
  return raw
    .split(/[,\n;]/)
    .map((s) => s.trim())
    .filter(Boolean);
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
