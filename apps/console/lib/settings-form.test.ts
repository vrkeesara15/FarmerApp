import { describe, expect, it } from "vitest";
import { DEFAULT_SETTINGS } from "./mock/admin";
import type { TenantSettings } from "./admin";
import {
  fieldForLoc,
  minutesTextToSeconds,
  paiseToRupeesText,
  rupeesTextToPaise,
  secondsToMinutesText,
  toForm,
  toPatch,
  toSettings,
  validateSettingsForm,
} from "./settings-form";

const settings = (): TenantSettings =>
  structuredClone({
    ...DEFAULT_SETTINGS,
    gstin_by_state: { "36": "36ABCDE1234F1Z5" },
    legal_name: "Farmers Care Centre Pvt Ltd",
  }) as unknown as TenantSettings;

describe("unit conversion", () => {
  it("shows paise as rupees and back", () => {
    expect(paiseToRupeesText(300)).toBe("3");
    expect(paiseToRupeesText(50_050)).toBe("500.50");
    expect(paiseToRupeesText(5_000_000)).toBe("50000");
    expect(rupeesTextToPaise("3")).toBe(300);
    expect(rupeesTextToPaise("500.5")).toBe(50_050);
    expect(rupeesTextToPaise("12.345")).toBeNull();
    expect(rupeesTextToPaise("-1")).toBeNull();
  });

  it("shows seconds as minutes and back", () => {
    expect(secondsToMinutesText(300)).toBe("5");
    expect(secondsToMinutesText(90)).toBe("1.5");
    expect(minutesTextToSeconds("5")).toBe(300);
    expect(minutesTextToSeconds("1.5")).toBe(90);
    expect(minutesTextToSeconds("abc")).toBeNull();
  });

  it("round-trips the API settings through the form", () => {
    const s = settings();
    const form = toForm(s);
    expect(form).toMatchObject({
      geofence_radius_m: "150",
      min_visit_minutes: "5",
      ta_rate_rupees: "3",
      credit_limit_rupees: "50000",
      variance_rupees: "500",
      auto_duty_end_local_time: "20:00",
      gstin_by_state: [{ state: "36", gstin: "36ABCDE1234F1Z5" }],
    });
    expect(toSettings(form)).toEqual(s);
    expect(toPatch(form, s)).toEqual({});
  });

  it("patches only the changed keys, in API units", () => {
    const s = settings();
    const form = {
      ...toForm(s),
      geofence_radius_m: "200",
      min_visit_minutes: "7.5",
      ta_rate_rupees: "4.25",
      sampling_moving_s: "60",
      app_name_agent: "FCC Mitra",
      primary_colour: "#aa3300",
      meeting_point_radius_m: "",
    };
    expect(toPatch(form, s)).toEqual({
      geofence_radius_m: 200,
      min_visit_duration_s: 450,
      ta_rate_per_km_paise: 425,
      sampling: { moving_s: 60 },
      branding: { app_name_agent: "FCC Mitra", primary_colour: "#AA3300" },
    });
  });
});

describe("validation mirrors the API ranges", () => {
  const valid = () => toForm(settings());

  it("accepts the defaults", () => {
    expect(validateSettingsForm(valid())).toEqual({});
  });

  it.each([
    ["geofence_radius_m", "9"],
    ["geofence_radius_m", "2001"],
    ["geofence_radius_m", "150.5"],
    ["meeting_point_radius_m", "5"],
    ["idle_end_minutes", "4"],
    ["sampling_moving_s", "29"],
    ["sampling_stationary_s", "7201"],
    ["sampling_upload_s", "59"],
    ["credit_due_days", "0"],
    ["webhook_replay_window_s", "86401"],
  ] as const)("rejects %s = %s with the range", (field, value) => {
    const errors = validateSettingsForm({ ...valid(), [field]: value });
    expect(errors[field]?.key).toBe("settings.errors.intRange");
    expect(errors[field]?.params).toHaveProperty("min");
  });

  it("checks rupees, minutes, times and identifiers", () => {
    const e = validateSettingsForm({
      ...valid(),
      ta_rate_rupees: "100.01",
      credit_limit_rupees: "abc",
      variance_rupees: "100000",
      min_visit_minutes: "1441",
      auto_duty_end_local_time: "24:00",
      invoice_prefix: "fcc",
      primary_colour: "green",
      support_phone: "12",
      app_name_farmer: "x".repeat(41),
      gstin_by_state: [
        { state: "36", gstin: "36ABCDE1234F1Z5" },
        { state: "27", gstin: "NOT-A-GSTIN" },
        { state: "36", gstin: "36ABCDE1234F1Z5" },
      ],
    });
    expect(e.ta_rate_rupees?.key).toBe("settings.errors.rupeeRange");
    expect(e.credit_limit_rupees?.key).toBe("settings.errors.rupeeRange");
    expect(e.variance_rupees).toBeUndefined();
    expect(e.min_visit_minutes?.key).toBe("settings.errors.minutesRange");
    expect(e.auto_duty_end_local_time?.key).toBe("settings.errors.time");
    expect(e.invoice_prefix?.key).toBe("settings.errors.invoicePrefix");
    expect(e.primary_colour?.key).toBe("settings.errors.colour");
    expect(e.support_phone?.key).toBe("settings.errors.phone");
    expect(e.app_name_farmer?.key).toBe("settings.errors.length");
    expect(e["gstin.1"]?.key).toBe("settings.errors.gstin");
    expect(e["gstin.2"]?.key).toBe("settings.errors.stateCode");
    expect(e["gstin.0"]).toBeUndefined();
  });

  it("needs at least one language and a default among them", () => {
    expect(validateSettingsForm({ ...valid(), languages_enabled: [] }).languages_enabled?.key).toBe(
      "settings.errors.languages",
    );
    expect(
      validateSettingsForm({ ...valid(), languages_enabled: ["te"], default_language: "en" })
        .default_language?.key,
    ).toBe("settings.errors.defaultLanguage");
  });

  it("maps API error locations to form fields", () => {
    expect(fieldForLoc(["body", "geofence_radius_m"])).toBe("geofence_radius_m");
    expect(fieldForLoc(["body", "min_visit_duration_s"])).toBe("min_visit_minutes");
    expect(fieldForLoc(["body", "sampling", "moving_s"])).toBe("sampling_moving_s");
    expect(fieldForLoc(["body", "branding", "primary_colour"])).toBe("primary_colour");
    expect(fieldForLoc(["body", "ta_rate_per_km_paise"])).toBe("ta_rate_rupees");
    expect(fieldForLoc(["body", "unknown"])).toBeNull();
  });
});
