import { describe, expect, it, afterEach } from "vitest";
import { t, setLocale, getLocale, interpolate, isLocale, fontClassFor, LOCALES } from "./i18n";
import en from "@/messages/en.json";
import te from "@/messages/te.json";
import kn from "@/messages/kn.json";
import hi from "@/messages/hi.json";
import mr from "@/messages/mr.json";

describe("i18n t()", () => {
  afterEach(() => setLocale("en"));

  it("returns the English message", () => {
    expect(t("login.title")).toBe(en.login.title);
  });

  it("interpolates params", () => {
    expect(t("login.otpSentTo", { phone: "98765 43210" })).toBe(
      "We sent a code to +91 98765 43210",
    );
    expect(interpolate("{a} and {b}", { a: 1, b: "x" })).toBe("1 and x");
    expect(interpolate("{missing}", {})).toBe("{missing}");
  });

  it("falls back to English for empty locales", () => {
    setLocale("te");
    expect(getLocale()).toBe("te");
    expect(t("nav.home")).toBe("Home");
  });

  it("other locale files are valid objects that only contain known keys", () => {
    for (const cat of [te, kn, hi, mr]) {
      expect(typeof cat).toBe("object");
      for (const k of Object.keys(cat)) expect(k in en).toBe(true);
    }
  });

  it("validates locales and maps fonts", () => {
    expect(isLocale("kn")).toBe(true);
    expect(isLocale("fr")).toBe(false);
    expect(LOCALES).toHaveLength(5);
    expect(fontClassFor("hi")).toBe("font-devanagari");
    expect(fontClassFor("en")).toBe("font-sans");
  });
});
