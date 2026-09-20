/**
 * WC-008 / AN-008 campaigns (C80 list, C81 builder, C82 results). Typed `/v1/campaigns*` calls
 * and the pure helpers the builder needs. Shapes mirror docs/prs/M7-growth-api.md.
 *
 * Consent (DPDP / NF-013) is not a criterion the console can switch off: every audience is the
 * farmers whose latest `(farmer, marketing)` consent row is a grant, and the API re-checks it
 * per batch at send time. `segmentCount` therefore always returns the consented count plus how
 * many matching farmers were excluded for consent — `consentNote()` turns that into the copy
 * the builder shows next to the number.
 */
import { authedFetch } from "./api";
import { LOCALES, type Locale } from "./i18n";

export const CAMPAIGN_CHANNELS = ["sms", "whatsapp", "push"] as const;
export type CampaignChannel = (typeof CAMPAIGN_CHANNELS)[number];

export const CAMPAIGN_STATUSES = [
  "draft",
  "scheduled",
  "sending",
  "sent",
  "cancelled",
  "failed",
] as const;
export type CampaignStatus = (typeof CAMPAIGN_STATUSES)[number];

export const RECIPIENT_STATUSES = [
  "pending",
  "sent",
  "delivered",
  "failed",
  "skipped",
  "holdout",
] as const;
export type RecipientStatus = (typeof RECIPIENT_STATUSES)[number];

/** Roles that read C80-C82 (`x-roles` of listCampaigns); only the first three write. */
export const CAMPAIGN_WRITE_ROLES: ReadonlyArray<string> = ["owner", "director", "tenant_admin"];
export const CAMPAIGN_READ_ROLES: ReadonlyArray<string> = [...CAMPAIGN_WRITE_ROLES, "auditor"];

export interface CampaignSegment {
  crop_ids?: string[];
  stages?: string[];
  districts?: string[];
  store_ids?: string[];
  purchase_within_days?: number;
  min_spend_paise?: number;
  no_purchase_within_days?: number;
  visited_within_days?: number;
  not_visited_within_days?: number;
  app_user?: boolean;
  app_active_within_days?: number;
  languages?: string[];
}

export interface SegmentCount {
  count: number;
  excluded_no_consent: number;
}

export interface Campaign {
  id: string;
  name: string;
  channel: CampaignChannel;
  status: CampaignStatus;
  segment: CampaignSegment;
  messages: Partial<Record<string, string>>;
  template_key: string | null;
  attribution_days: number;
  holdout_pct: number;
  notes: string | null;
  audience: number | null;
  send_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CampaignRecipient {
  farmer_id: string;
  farmer_name: string;
  phone_masked: string;
  arm: "target" | "holdout";
  language: string;
  status: RecipientStatus;
  skip_reason: string | null;
  dlt_template_id: string | null;
  sent_at: string | null;
  delivered_at: string | null;
  opened_at: string | null;
  error: string | null;
}

export interface CampaignRecipientPage {
  items: CampaignRecipient[];
  next_cursor?: string | null;
  counts: Record<string, number>;
}

export interface CampaignHoldout {
  audience: number;
  orders: number;
  converted_farmers: number;
  conversion_rate: number | null;
  revenue_paise: number;
  own_brand_revenue_paise: number;
  own_brand_share: number | null;
}

export interface CampaignRoi {
  audience: number;
  sent: number;
  delivered: number;
  failed: number;
  skipped: number;
  opened: number | null;
  orders: number;
  converted_farmers: number;
  conversion_rate: number | null;
  revenue_paise: number;
  own_brand_revenue_paise: number;
  own_brand_share: number | null;
  attribution_days: number;
  holdout: CampaignHoldout | null;
  own_brand_lift: number | null;
  conversion_lift: number | null;
}

export interface CampaignInput {
  name: string;
  channel: CampaignChannel;
  segment: CampaignSegment;
  messages: Record<string, string>;
  template_key?: string | null;
  attribution_days?: number;
  holdout_pct?: number;
  notes?: string | null;
}

export interface CampaignPage {
  items: Campaign[];
  next_cursor?: string | null;
}

const qs = (params: Record<string, string | number | undefined>): string => {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params))
    if (v !== undefined && v !== "") sp.set(k, String(v));
  const s = sp.toString();
  return s ? `?${s}` : "";
};

export const campaignsApi = {
  segmentCount: (segment: CampaignSegment) =>
    authedFetch<SegmentCount>("v1/campaigns/segment-count", { body: { segment } }),
  list: (filters: { status?: string; cursor?: string | null } = {}) =>
    authedFetch<CampaignPage>(
      `v1/campaigns${qs({ status: filters.status, cursor: filters.cursor ?? undefined })}`,
    ),
  get: (id: string) => authedFetch<Campaign>(`v1/campaigns/${id}`),
  create: (body: CampaignInput) => authedFetch<Campaign>("v1/campaigns", { body }),
  patch: (id: string, body: Partial<CampaignInput>) =>
    authedFetch<Campaign>(`v1/campaigns/${id}`, { method: "PATCH", body }),
  schedule: (id: string, sendAt: string | null) =>
    authedFetch<Campaign>(`v1/campaigns/${id}/schedule`, {
      body: sendAt ? { send_at: sendAt } : {},
    }),
  cancel: (id: string) => authedFetch<Campaign>(`v1/campaigns/${id}/cancel`, { method: "POST" }),
  recipients: (id: string, filters: { status?: string; cursor?: string | null } = {}) =>
    authedFetch<CampaignRecipientPage>(
      `v1/campaigns/${id}/recipients${qs({
        status: filters.status,
        cursor: filters.cursor ?? undefined,
      })}`,
    ),
  roi: (id: string) => authedFetch<CampaignRoi>(`v1/campaigns/${id}/roi`),
};

// ---- pure helpers (unit-tested) ------------------------------------------------------------

/** SMS is billed per 160-character part; the builder warns past one part. */
export const SMS_PART_CHARS = 160;
export const MESSAGE_MAX_CHARS = 1000;

export function smsParts(text: string): number {
  return text.length === 0 ? 0 : Math.ceil(text.length / SMS_PART_CHARS);
}

export interface CampaignDraft {
  name: string;
  channel: CampaignChannel;
  segment: CampaignSegment;
  messages: Partial<Record<Locale, string>>;
  holdout_pct: number;
  attribution_days: number;
  send_at: string | null;
}

export type CampaignField =
  | "name"
  | "segment"
  | "messages"
  | "holdout_pct"
  | "attribution_days"
  | "send_at";

export interface DraftIssue {
  field: CampaignField;
  /** i18n key suffix under `campaigns.error.` */
  code: string;
}

/**
 * The `send at` field is IST (the screen says so and the API stores UTC), so the console reads
 * a bare `YYYY-MM-DDTHH:mm` from the datetime-local input as +05:30 rather than as the
 * browser's own zone. Returns null when the value is not a date and time.
 */
export const IST_OFFSET = "+05:30";

export function sendAtToIso(local: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(local)) return null;
  const at = new Date(`${local}:00${IST_OFFSET}`);
  return Number.isNaN(at.getTime()) ? null : at.toISOString();
}

export function isEmptySegment(segment: CampaignSegment): boolean {
  return Object.values(segment).every(
    (v) => v === undefined || v === null || v === "" || (Array.isArray(v) && v.length === 0),
  );
}

/** Languages the draft carries a non-empty message for, in catalogue order. */
export function filledLanguages(messages: Partial<Record<Locale, string>>): Locale[] {
  return LOCALES.filter((l) => (messages[l] ?? "").trim().length > 0);
}

/**
 * Client-side validation of the C81 builder before `POST /v1/campaigns` (the API validates
 * again). The default language `en` must be present: it is what a farmer whose language has no
 * message receives.
 */
export function validateDraft(draft: CampaignDraft, now = new Date()): DraftIssue[] {
  const issues: DraftIssue[] = [];
  if (draft.name.trim().length < 3) issues.push({ field: "name", code: "nameTooShort" });
  if (draft.name.length > 120) issues.push({ field: "name", code: "nameTooLong" });
  if (isEmptySegment(draft.segment)) issues.push({ field: "segment", code: "segmentEmpty" });
  const filled = filledLanguages(draft.messages);
  if (filled.length === 0) issues.push({ field: "messages", code: "messageRequired" });
  else if (!filled.includes("en")) issues.push({ field: "messages", code: "defaultLanguage" });
  if (filled.some((l) => (draft.messages[l] ?? "").length > MESSAGE_MAX_CHARS))
    issues.push({ field: "messages", code: "messageTooLong" });
  if (!Number.isInteger(draft.holdout_pct) || draft.holdout_pct < 0 || draft.holdout_pct > 50)
    issues.push({ field: "holdout_pct", code: "holdoutRange" });
  if (
    !Number.isInteger(draft.attribution_days) ||
    draft.attribution_days < 1 ||
    draft.attribution_days > 90
  )
    issues.push({ field: "attribution_days", code: "attributionRange" });
  if (draft.send_at) {
    const iso = sendAtToIso(draft.send_at);
    if (iso === null) issues.push({ field: "send_at", code: "sendAtInvalid" });
    else if (new Date(iso).getTime() <= now.getTime())
      issues.push({ field: "send_at", code: "sendAtPast" });
  }
  return issues;
}

export interface ConsentNote {
  /** `campaigns.consent.<key>` i18n key. */
  key: "consentedOnly" | "consentedOnlyExcluded" | "consentedNone";
  params: { count: number; excluded: number };
}

/**
 * The consented-count message shown under the live count. Never states a plain audience size:
 * the number is always named as "farmers with marketing consent", and when consent excluded
 * anyone the line says how many were left out and why.
 */
export function consentNote(count: SegmentCount | undefined): ConsentNote {
  const c = count?.count ?? 0;
  const excluded = count?.excluded_no_consent ?? 0;
  if (c === 0) return { key: "consentedNone", params: { count: 0, excluded } };
  if (excluded > 0) return { key: "consentedOnlyExcluded", params: { count: c, excluded } };
  return { key: "consentedOnly", params: { count: c, excluded: 0 } };
}

/** Target / holdout split the API will freeze (deterministic, rounded down for the holdout). */
export function splitArms(
  audience: number,
  holdoutPct: number,
): { target: number; holdout: number } {
  const holdout = Math.floor((audience * holdoutPct) / 100);
  return { target: audience - holdout, holdout };
}

/** A ratio expressed as lift in percentage points of the holdout (null when not measurable). */
export function liftText(lift: number | null | undefined): number | null {
  return typeof lift === "number" && Number.isFinite(lift) ? lift : null;
}
