/**
 * C102 settings form (WC-012): the typed `TenantSettings` of `GET /v1/settings` shown in the units
 * people think in (metres, minutes, rupees, IST clock times) and converted back to the API's
 * units (seconds, integer paise) for `PATCH /v1/settings`. Validation mirrors the ranges of
 * apps/api/farmerapp/tenants/settings.py (the API stays the authority: 422 `invalid_settings`).
 */
import type { MessageKey, Params } from "./i18n";
import { LANGUAGES, type Language, type SettingsPatch, type TenantSettings } from "./admin";

export interface GstinRow {
  state: string;
  gstin: string;
}

/** Form values: text inputs are strings, as typed. */
export interface SettingsFormValues {
  geofence_radius_m: string;
  meeting_point_radius_m: string;
  min_visit_minutes: string;
  consent_version: string;
  auto_duty_end_local_time: string;
  idle_end_minutes: string;
  location_policy_version: string;
  sampling_moving_s: string;
  sampling_stationary_s: string;
  sampling_upload_s: string;
  ta_rate_rupees: string;
  credit_limit_rupees: string;
  credit_due_days: string;
  variance_rupees: string;
  webhook_replay_window_s: string;
  legal_name: string;
  invoice_prefix: string;
  gstin_by_state: GstinRow[];
  languages_enabled: Language[];
  default_language: Language;
  app_name_agent: string;
  app_name_farmer: string;
  primary_colour: string;
  logo_blob_uri: string;
  support_phone: string;
}

export type SettingsField = Exclude<keyof SettingsFormValues, "gstin_by_state"> | `gstin.${number}`;

export interface FieldError {
  key: MessageKey;
  params?: Params;
}
export type SettingsErrors = Partial<Record<SettingsField, FieldError>>;

/** Integer ranges in the form's units (API ranges converted). */
export const RANGES = {
  geofence_radius_m: { min: 10, max: 2000, unit: "m" },
  meeting_point_radius_m: { min: 10, max: 2000, unit: "m" },
  idle_end_minutes: { min: 5, max: 720, unit: "min" },
  sampling_moving_s: { min: 30, max: 3600, unit: "s" },
  sampling_stationary_s: { min: 60, max: 7200, unit: "s" },
  sampling_upload_s: { min: 60, max: 86_400, unit: "s" },
  credit_due_days: { min: 1, max: 730, unit: "days" },
  webhook_replay_window_s: { min: 30, max: 86_400, unit: "s" },
} as const;

/** Rupee ranges (API paise / 100). */
export const RUPEE_RANGES = {
  ta_rate_rupees: { min: 0, max: 100 },
  credit_limit_rupees: { min: 0, max: 100_000_000 },
  variance_rupees: { min: 0, max: 100_000 },
} as const;

/** min_visit_duration_s 0-86,400 s shown in minutes. */
export const MIN_VISIT_MAX_MINUTES = 1440;

const INT = /^\d+$/;
const RUPEES = /^\d+(\.\d{1,2})?$/;
const MINUTES = /^\d+(\.\d{1,2})?$/;
export const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;
export const HEX_COLOUR = /^#[0-9A-Fa-f]{6}$/;
export const GSTIN_PATTERN = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const PHONE = /^\+?[0-9]{8,15}$/;
const PREFIX = /^[A-Z0-9]{1,8}$/;

// ---- conversions ---------------------------------------------------------------------------
export function paiseToRupeesText(paise: number): string {
  const whole = Math.trunc(paise / 100);
  const frac = Math.abs(paise % 100);
  return frac === 0 ? String(whole) : `${whole}.${String(frac).padStart(2, "0")}`;
}

export function rupeesTextToPaise(value: string): number | null {
  const v = value.trim();
  if (!RUPEES.test(v)) return null;
  const [whole = "0", frac = ""] = v.split(".");
  return Number(whole) * 100 + Number(frac.padEnd(2, "0"));
}

export function secondsToMinutesText(seconds: number): string {
  const m = seconds / 60;
  return Number.isInteger(m) ? String(m) : String(Math.round(m * 100) / 100);
}

export function minutesTextToSeconds(value: string): number | null {
  const v = value.trim();
  if (!MINUTES.test(v)) return null;
  return Math.round(Number(v) * 60);
}

export function toForm(s: TenantSettings): SettingsFormValues {
  return {
    geofence_radius_m: String(s.geofence_radius_m),
    meeting_point_radius_m:
      s.meeting_point_radius_m === null ? "" : String(s.meeting_point_radius_m),
    min_visit_minutes: secondsToMinutesText(s.min_visit_duration_s),
    consent_version: s.consent_version,
    auto_duty_end_local_time: s.auto_duty_end_local_time,
    idle_end_minutes: String(s.idle_end_minutes),
    location_policy_version: s.location_policy_version,
    sampling_moving_s: String(s.sampling.moving_s),
    sampling_stationary_s: String(s.sampling.stationary_s),
    sampling_upload_s: String(s.sampling.upload_s),
    ta_rate_rupees: paiseToRupeesText(s.ta_rate_per_km_paise),
    credit_limit_rupees: paiseToRupeesText(s.store_manager_max_credit_limit_paise),
    credit_due_days: String(s.credit_due_days),
    variance_rupees: paiseToRupeesText(s.day_close_variance_threshold_paise),
    webhook_replay_window_s: String(s.webhook_replay_window_s),
    legal_name: s.legal_name ?? "",
    invoice_prefix: s.invoice_prefix ?? "",
    gstin_by_state: Object.entries(s.gstin_by_state)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([state, gstin]) => ({ state, gstin })),
    languages_enabled: LANGUAGES.filter((l) => s.languages_enabled.includes(l)),
    default_language: s.default_language,
    app_name_agent: s.branding.app_name_agent ?? "",
    app_name_farmer: s.branding.app_name_farmer ?? "",
    primary_colour: s.branding.primary_colour,
    logo_blob_uri: s.branding.logo_blob_uri ?? "",
    support_phone: s.branding.support_phone ?? "",
  };
}

const orNull = (v: string): string | null => (v.trim() === "" ? null : v.trim());
const int = (v: string): number => Number(v.trim());

/** Valid form values -> the full settings object in API units. */
export function toSettings(v: SettingsFormValues): TenantSettings {
  return {
    consent_version: v.consent_version.trim(),
    geofence_radius_m: int(v.geofence_radius_m),
    meeting_point_radius_m:
      v.meeting_point_radius_m.trim() === "" ? null : int(v.meeting_point_radius_m),
    min_visit_duration_s: minutesTextToSeconds(v.min_visit_minutes) ?? 0,
    auto_duty_end_local_time: v.auto_duty_end_local_time,
    idle_end_minutes: int(v.idle_end_minutes),
    location_policy_version: v.location_policy_version.trim(),
    sampling: {
      moving_s: int(v.sampling_moving_s),
      stationary_s: int(v.sampling_stationary_s),
      upload_s: int(v.sampling_upload_s),
    },
    ta_rate_per_km_paise: rupeesTextToPaise(v.ta_rate_rupees) ?? 0,
    store_manager_max_credit_limit_paise: rupeesTextToPaise(v.credit_limit_rupees) ?? 0,
    credit_due_days: int(v.credit_due_days),
    day_close_variance_threshold_paise: rupeesTextToPaise(v.variance_rupees) ?? 0,
    webhook_replay_window_s: int(v.webhook_replay_window_s),
    legal_name: orNull(v.legal_name),
    gstin_by_state: Object.fromEntries(
      v.gstin_by_state
        .filter((r) => r.state.trim() || r.gstin.trim())
        .map((r) => [r.state.trim(), r.gstin.trim()]),
    ),
    invoice_prefix: orNull(v.invoice_prefix),
    languages_enabled: LANGUAGES.filter((l) => v.languages_enabled.includes(l)),
    default_language: v.default_language,
    branding: {
      app_name_agent: orNull(v.app_name_agent),
      app_name_farmer: orNull(v.app_name_farmer),
      primary_colour: v.primary_colour.toUpperCase(),
      logo_blob_uri: orNull(v.logo_blob_uri),
      support_phone: orNull(v.support_phone),
    },
  };
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

/** Only the keys that changed (nested sampling / branding key by key); `{}` when nothing did. */
export function toPatch(v: SettingsFormValues, original: TenantSettings): SettingsPatch {
  const next = toSettings(v);
  const patch: Record<string, unknown> = {};
  for (const key of Object.keys(next) as Array<keyof TenantSettings>) {
    if (key === "sampling" || key === "branding") {
      const sub: Record<string, unknown> = {};
      const a = next[key] as unknown as Record<string, unknown>;
      const b = original[key] as unknown as Record<string, unknown>;
      for (const k of Object.keys(a)) if (!same(a[k], b[k])) sub[k] = a[k];
      if (Object.keys(sub).length) patch[key] = sub;
    } else if (!same(next[key], original[key])) patch[key] = next[key];
  }
  return patch as SettingsPatch;
}

// ---- validation ----------------------------------------------------------------------------
export function validateSettingsForm(v: SettingsFormValues): SettingsErrors {
  const e: SettingsErrors = {};
  const intRange = (field: keyof typeof RANGES, optional = false) => {
    const raw = v[field].trim();
    if (optional && raw === "") return;
    const { min, max, unit } = RANGES[field];
    if (!INT.test(raw) || int(raw) < min || int(raw) > max)
      e[field] = { key: "settings.errors.intRange", params: { min, max, unit } };
  };
  intRange("geofence_radius_m");
  intRange("meeting_point_radius_m", true);
  intRange("idle_end_minutes");
  intRange("sampling_moving_s");
  intRange("sampling_stationary_s");
  intRange("sampling_upload_s");
  intRange("credit_due_days");
  intRange("webhook_replay_window_s");

  const seconds = minutesTextToSeconds(v.min_visit_minutes);
  if (seconds === null || seconds > MIN_VISIT_MAX_MINUTES * 60)
    e.min_visit_minutes = {
      key: "settings.errors.minutesRange",
      params: { min: 0, max: MIN_VISIT_MAX_MINUTES },
    };

  for (const field of Object.keys(RUPEE_RANGES) as Array<keyof typeof RUPEE_RANGES>) {
    const paise = rupeesTextToPaise(v[field]);
    const { min, max } = RUPEE_RANGES[field];
    if (paise === null || paise < min * 100 || paise > max * 100)
      e[field] = { key: "settings.errors.rupeeRange", params: { min, max } };
  }

  if (!TIME_PATTERN.test(v.auto_duty_end_local_time))
    e.auto_duty_end_local_time = { key: "settings.errors.time" };
  for (const field of ["consent_version", "location_policy_version"] as const) {
    const len = v[field].trim().length;
    if (len < 1 || len > 32)
      e[field] = { key: "settings.errors.length", params: { min: 1, max: 32 } };
  }
  if (v.legal_name.trim().length > 200)
    e.legal_name = { key: "settings.errors.length", params: { min: 1, max: 200 } };
  if (v.invoice_prefix.trim() !== "" && !PREFIX.test(v.invoice_prefix.trim()))
    e.invoice_prefix = { key: "settings.errors.invoicePrefix" };

  const states = new Set<string>();
  v.gstin_by_state.forEach((row, i) => {
    const state = row.state.trim();
    const gstin = row.gstin.trim();
    if (!state && !gstin) return;
    if (!/^\d{2}$/.test(state) || states.has(state))
      e[`gstin.${i}`] = { key: "settings.errors.stateCode" };
    else if (!GSTIN_PATTERN.test(gstin)) e[`gstin.${i}`] = { key: "settings.errors.gstin" };
    states.add(state);
  });

  if (v.languages_enabled.length === 0) e.languages_enabled = { key: "settings.errors.languages" };
  else if (!v.languages_enabled.includes(v.default_language))
    e.default_language = { key: "settings.errors.defaultLanguage" };

  for (const field of ["app_name_agent", "app_name_farmer"] as const)
    if (v[field].trim().length > 40)
      e[field] = { key: "settings.errors.length", params: { min: 1, max: 40 } };
  if (!HEX_COLOUR.test(v.primary_colour)) e.primary_colour = { key: "settings.errors.colour" };
  if (v.support_phone.trim() !== "" && !PHONE.test(v.support_phone.trim()))
    e.support_phone = { key: "settings.errors.phone" };
  if (v.logo_blob_uri.trim().length > 512)
    e.logo_blob_uri = { key: "settings.errors.length", params: { min: 1, max: 512 } };
  return e;
}

/** Map a 422 `invalid_settings` error location (`["body", "sampling", "moving_s"]`) to a form field. */
export function fieldForLoc(loc: ReadonlyArray<string>): SettingsField | null {
  const path = loc[0] === "body" ? loc.slice(1) : [...loc];
  const [a, b] = path;
  const map: Record<string, SettingsField> = {
    geofence_radius_m: "geofence_radius_m",
    meeting_point_radius_m: "meeting_point_radius_m",
    min_visit_duration_s: "min_visit_minutes",
    consent_version: "consent_version",
    auto_duty_end_local_time: "auto_duty_end_local_time",
    idle_end_minutes: "idle_end_minutes",
    location_policy_version: "location_policy_version",
    ta_rate_per_km_paise: "ta_rate_rupees",
    store_manager_max_credit_limit_paise: "credit_limit_rupees",
    credit_due_days: "credit_due_days",
    day_close_variance_threshold_paise: "variance_rupees",
    webhook_replay_window_s: "webhook_replay_window_s",
    legal_name: "legal_name",
    invoice_prefix: "invoice_prefix",
    languages_enabled: "languages_enabled",
    default_language: "default_language",
  };
  if (a === "sampling" && b) return `sampling_${b}_s`.replace("_s_s", "_s") as SettingsField;
  if (a === "branding" && b) return b as SettingsField;
  return a ? (map[a] ?? null) : null;
}

/** Default app names when branding leaves them null (the apps' i18n defaults). */
export const DEFAULT_APP_NAMES = { agent: "Mitra", farmer: "Kisan" } as const;
/** `Branding.primary_colour` default (apps/api TenantSettings). */
export const DEFAULT_PRIMARY_COLOUR = "#1F6B3A";
