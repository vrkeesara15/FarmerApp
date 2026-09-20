import { describe, expect, it } from "vitest";
import {
  consentNote,
  filledLanguages,
  isEmptySegment,
  smsParts,
  splitArms,
  validateDraft,
  type CampaignDraft,
} from "./campaigns";

const draft = (over: Partial<CampaignDraft> = {}): CampaignDraft => ({
  name: "Cotton advisory",
  channel: "sms",
  segment: { crop_ids: ["crop-cotton"] },
  messages: { en: "Scout your cotton this week." },
  holdout_pct: 10,
  attribution_days: 14,
  send_at: null,
  ...over,
});

describe("C81 campaign draft validation", () => {
  it("accepts a complete draft", () => {
    expect(validateDraft(draft())).toEqual([]);
  });

  it("requires a name, a segment criterion and a message", () => {
    const issues = validateDraft(draft({ name: "ab", segment: {}, messages: {} }));
    expect(issues.map((i) => i.code).sort()).toEqual([
      "messageRequired",
      "nameTooShort",
      "segmentEmpty",
    ]);
  });

  it("requires English as the fallback language", () => {
    const issues = validateDraft(draft({ messages: { te: "వరి" } }));
    expect(issues).toEqual([{ field: "messages", code: "defaultLanguage" }]);
  });

  it("caps the message length", () => {
    const issues = validateDraft(draft({ messages: { en: "x".repeat(1001) } }));
    expect(issues.map((i) => i.code)).toContain("messageTooLong");
  });

  it("keeps the holdout between 0 and 50 and the window between 1 and 90 days", () => {
    expect(validateDraft(draft({ holdout_pct: 60 })).map((i) => i.code)).toEqual(["holdoutRange"]);
    expect(validateDraft(draft({ holdout_pct: 2.5 })).map((i) => i.code)).toEqual(["holdoutRange"]);
    expect(validateDraft(draft({ attribution_days: 0 })).map((i) => i.code)).toEqual([
      "attributionRange",
    ]);
  });

  it("refuses a send time in the past", () => {
    const now = new Date("2026-09-19T10:00:00Z");
    expect(validateDraft(draft({ send_at: "2026-09-19T09:00" }), now).map((i) => i.code)).toEqual([
      "sendAtPast",
    ]);
    expect(validateDraft(draft({ send_at: "2026-09-20T09:00" }), now)).toEqual([]);
    expect(validateDraft(draft({ send_at: "not a date" }), now).map((i) => i.code)).toEqual([
      "sendAtInvalid",
    ]);
  });

  it("knows an empty segment and the filled languages", () => {
    expect(isEmptySegment({})).toBe(true);
    expect(isEmptySegment({ crop_ids: [] })).toBe(true);
    expect(isEmptySegment({ app_user: false })).toBe(false);
    expect(filledLanguages({ te: " ", en: "hi", hi: "नमस्ते" })).toEqual(["en", "hi"]);
  });

  it("counts SMS parts", () => {
    expect(smsParts("")).toBe(0);
    expect(smsParts("x".repeat(160))).toBe(1);
    expect(smsParts("x".repeat(161))).toBe(2);
  });
});

describe("consented-count messaging (WC-008: consent is never optional)", () => {
  it("names the number as farmers with marketing consent", () => {
    expect(consentNote({ count: 120, excluded_no_consent: 0 })).toEqual({
      key: "consentedOnly",
      params: { count: 120, excluded: 0 },
    });
  });

  it("says how many matching farmers consent left out", () => {
    expect(consentNote({ count: 120, excluded_no_consent: 31 })).toEqual({
      key: "consentedOnlyExcluded",
      params: { count: 120, excluded: 31 },
    });
  });

  it("does not claim an audience when nothing consented", () => {
    expect(consentNote({ count: 0, excluded_no_consent: 8 })).toEqual({
      key: "consentedNone",
      params: { count: 0, excluded: 8 },
    });
    expect(consentNote(undefined).key).toBe("consentedNone");
  });
});

describe("holdout split", () => {
  it("rounds the holdout down and gives the rest the message", () => {
    expect(splitArms(105, 10)).toEqual({ target: 95, holdout: 10 });
    expect(splitArms(9, 10)).toEqual({ target: 9, holdout: 0 });
    expect(splitArms(100, 0)).toEqual({ target: 100, holdout: 0 });
  });
});
