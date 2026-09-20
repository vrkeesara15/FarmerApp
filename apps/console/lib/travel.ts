/**
 * FA-023 travel allowance approvals (C91). Typed `/v1/travel/*` calls plus the helpers the
 * screen needs to put the **computed** km of a claim day next to what the officer claimed.
 * Shapes mirror apps/api/farmerapp/travel/schemas.py.
 */
import { authedFetch } from "./api";

export const CLAIM_TYPES = ["fuel", "bus", "other"] as const;
export type ClaimType = (typeof CLAIM_TYPES)[number];

export const CLAIM_STATUSES = ["submitted", "approved", "rejected"] as const;
export type ClaimStatus = (typeof CLAIM_STATUSES)[number];

/** Cluster heads decide their own cluster's claims; admins decide any (`x-roles`). */
export const CLAIM_DECIDE_ROLES: ReadonlyArray<string> = [
  "cluster_head",
  "owner",
  "director",
  "tenant_admin",
];
export const CLAIM_READ_ROLES: ReadonlyArray<string> = [
  ...CLAIM_DECIDE_ROLES,
  "auditor",
  "accountant",
  "field_officer",
];

export interface TravelClaim {
  id: string;
  tenant_id: string;
  officer_id: string;
  officer_name?: string | null;
  claim_date: string;
  type: ClaimType | string;
  amount_paise: number;
  receipt_uri: string;
  /** Signed URL of the receipt photo (the API serves one with the row). */
  receipt_url?: string | null;
  note: string | null;
  km_computed: number | string | null;
  status: ClaimStatus | string;
  decided_by: string | null;
  decided_at: string | null;
  decision_note: string | null;
  created_at: string;
  updated_at: string;
  version: number;
}

export interface TravelClaimPage {
  items: TravelClaim[];
  next_cursor?: string | null;
}

export interface TravelDay {
  date: string;
  sessions: number;
  km: number | string;
  km_capped: number | string;
  cap_km: number;
  rate_per_km_paise: number;
  ta_paise: number;
  open_session: boolean;
}

export interface TravelStatement {
  officer_id: string;
  officer_name?: string | null;
  month: string;
  rate_per_km_paise: number;
  cap_km: number;
  days: TravelDay[];
  km_total: number | string;
  km_capped_total: number | string;
  ta_total_paise: number;
  claims: TravelClaim[];
  claims_submitted_paise: number;
  claims_approved_paise: number;
  claims_rejected_paise: number;
  payable_paise: number;
}

const qs = (params: Record<string, string | undefined>): string => {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) sp.set(k, v);
  const s = sp.toString();
  return s ? `?${s}` : "";
};

export const travelApi = {
  claims: (filters: { status?: string; officer_id?: string; cursor?: string | null } = {}) =>
    authedFetch<TravelClaimPage>(
      `v1/travel/claims${qs({
        status: filters.status,
        officer_id: filters.officer_id,
        cursor: filters.cursor ?? undefined,
      })}`,
    ),
  claim: (id: string) => authedFetch<TravelClaim>(`v1/travel/claims/${id}`),
  approve: (id: string, note: string | null) =>
    authedFetch<TravelClaim>(`v1/travel/claims/${id}/approve`, { body: { note } }),
  reject: (id: string, note: string | null) =>
    authedFetch<TravelClaim>(`v1/travel/claims/${id}/reject`, { body: { note } }),
  statement: (month: string, officerId: string) =>
    authedFetch<TravelStatement>(`v1/travel/statement${qs({ month, officer_id: officerId })}`),
};

// ---- pure helpers -------------------------------------------------------------------------

export const num = (v: number | string | null | undefined): number | null => {
  if (v === null || v === undefined) return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
};

/** `YYYY-MM` of a claim date, so claims group by the month they belong to. */
export function claimMonth(claimDate: string): string {
  return claimDate.slice(0, 7);
}

/** The statement day that matches a claim (computed km vs claimed amount). */
export function dayFor(
  statement: TravelStatement | undefined,
  date: string,
): TravelDay | undefined {
  return statement?.days.find((d) => d.date === date);
}

/** Travel allowance already paid for the claim's day, in paise (null without a statement). */
export function allowanceFor(statement: TravelStatement | undefined, date: string): number | null {
  const day = dayFor(statement, date);
  return day ? day.ta_paise : null;
}
