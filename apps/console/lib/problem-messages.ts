/**
 * problem+json `code` -> message key (SPEC 8.3: clients switch on `code`, never on `title`).
 * Screens call `problemMessage(err, t)` and show the text inline (field / row / dialog error).
 */
import { ApiError } from "./api";
import type { MessageKey, TFunction } from "./i18n";

const CODES: Record<string, MessageKey> = {
  barcode_exists: "problems.barcodeExists",
  product_exists: "problems.productExists",
  price_above_mrp: "problems.priceAboveMrp",
  price_overlap: "problems.priceOverlap",
  claim_duplicate: "problems.claimDuplicate",
  claim_category_invalid: "problems.claimCategoryInvalid",
  pest_not_for_crop: "problems.pestNotForCrop",
  claim_not_draft: "problems.claimNotDraft",
  claim_retired: "problems.claimRetired",
  version_conflict: "problems.versionConflict",
  validation_error: "problems.validation",
  forbidden: "problems.forbidden",
  unauthenticated: "problems.unauthenticated",
  token_expired: "problems.unauthenticated",
  not_found: "problems.notFound",
  // SEC-028 step-up, WC-010 flags, WC-011 users, WC-012 settings
  step_up_required: "problems.stepUpRequired",
  otp_invalid: "problems.otpInvalid",
  otp_expired: "problems.otpExpired",
  otp_locked: "problems.otpLocked",
  otp_rate_limited: "problems.otpRateLimited",
  otp_not_found: "problems.otpNotFound",
  invalid_transition: "problems.invalidTransition",
  flag_resolved: "problems.flagResolved",
  assignee_invalid: "problems.assigneeInvalid",
  phone_taken: "problems.phoneTaken",
  invalid_assignment: "problems.invalidAssignment",
  role_not_grantable: "problems.roleNotGrantable",
  cannot_modify_self: "problems.cannotModifySelf",
  invalid_settings: "problems.invalidSettings",
};

export function problemCode(err: unknown): string | undefined {
  return err instanceof ApiError ? err.problem.code : undefined;
}

export function problemMessageKey(err: unknown): MessageKey {
  if (err instanceof ApiError) {
    if (err.status === 0) return "problems.network";
    const key = err.problem.code ? CODES[err.problem.code] : undefined;
    if (key) return key;
  }
  return "problems.default";
}

export function problemMessage(err: unknown, t: TFunction): string {
  return t(problemMessageKey(err));
}

/** Field-level validation problems (`errors[].loc` = ["body", "<field>"]) by field name. */
export function fieldErrors(err: unknown): Record<string, string> {
  if (!(err instanceof ApiError) || !err.problem.errors) return {};
  const out: Record<string, string> = {};
  for (const e of err.problem.errors) {
    const field = e.loc[e.loc.length - 1];
    if (field && !(field in out)) out[field] = e.msg ?? e.type ?? "";
  }
  return out;
}
