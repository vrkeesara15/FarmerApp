import * as React from "react";
import { act, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  DEFAULT_LOCALE,
  LOCALES,
  LOCALE_OPTIONS,
  LOCALE_STORAGE_KEY,
  fontClassFor,
  getLocale,
  initLocaleFromStorage,
  interpolate,
  isLocale,
  localeInitScript,
  setLocale,
  t,
  type Locale,
} from "./i18n";
import { useT } from "./i18n-client";
import en from "@/messages/en.json";
import te from "@/messages/te.json";
import kn from "@/messages/kn.json";
import hi from "@/messages/hi.json";
import mr from "@/messages/mr.json";

type Dict = { [k: string]: string | Dict };
function flatten(dict: Dict, prefix = ""): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(dict)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (typeof v === "string") out[key] = v;
    else Object.assign(out, flatten(v, key));
  }
  return out;
}
const placeholders = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

function Probe() {
  const t = useT();
  return React.createElement("h1", null, t("nav.home"));
}

describe("i18n t()", () => {
  beforeEach(() => {
    localStorage.clear();
    act(() => setLocale("en", { persist: false }));
  });
  afterEach(() => {
    localStorage.clear();
    act(() => setLocale("en", { persist: false }));
  });

  it("returns the English message", () => {
    expect(t("login.title")).toBe(en.login.title);
  });

  it("interpolates params", () => {
    expect(t("login.otpSentTo", { phone: "+91******3210" })).toBe(
      "We sent a code to +91******3210",
    );
    expect(interpolate("{a} and {b}", { a: 1, b: "x" })).toBe("1 and x");
    expect(interpolate("{missing}", {})).toBe("{missing}");
  });

  it("uses the current locale and an explicit locale argument", () => {
    setLocale("te");
    expect(getLocale()).toBe("te");
    expect(t("nav.home")).toBe(te.nav.home);
    expect(t("nav.home", undefined, "hi")).toBe(hi.nav.home);
    expect(t("login.attemptsLeft", { n: 2 }, "kn")).toBe(kn.login.attemptsLeft.replace("{n}", "2"));
  });

  it("validates locales and maps fonts", () => {
    expect(isLocale("kn")).toBe(true);
    expect(isLocale("fr")).toBe(false);
    expect(LOCALES).toHaveLength(5);
    expect(DEFAULT_LOCALE).toBe("en");
    expect(fontClassFor("hi")).toBe("font-devanagari");
    expect(fontClassFor("en")).toBe("font-sans");
  });

  it("offers every launch language with a literal script name", () => {
    expect(LOCALE_OPTIONS.map((o) => o.locale)).toEqual([...LOCALES]);
    expect(LOCALE_OPTIONS.map((o) => o.nativeName)).toEqual([
      "English",
      "తెలుగు",
      "ಕನ್ನಡ",
      "हिन्दी",
      "मराठी",
    ]);
    for (const o of LOCALE_OPTIONS)
      expect(t(o.nameKey, undefined, "en")).toBe(en.language[o.locale]);
  });
});

describe("i18n catalogues (FA-004: five launch languages, no missing keys)", () => {
  const flatEn = flatten(en);

  it("en.json is the template", () => {
    expect(Object.keys(flatEn).length).toBeGreaterThan(120);
  });

  for (const [locale, cat] of Object.entries({ te, kn, hi, mr }) as [Locale, Dict][]) {
    it(`${locale}.json translates every English key with the same placeholders`, () => {
      const flat = flatten(cat);
      const missing = Object.keys(flatEn).filter((k) => !(k in flat));
      const extra = Object.keys(flat).filter((k) => !(k in flatEn));
      expect(missing, `missing in ${locale}.json`).toEqual([]);
      expect(extra, `unknown keys in ${locale}.json`).toEqual([]);
      for (const [key, value] of Object.entries(flat)) {
        expect(value.trim(), `${key} is empty in ${locale}`).not.toBe("");
        expect(placeholders(value), `${key} placeholders in ${locale}`).toEqual(
          placeholders(flatEn[key]!),
        );
      }
    });
  }
});

describe("locale store (switch without reload)", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.lang = "";
    act(() => setLocale("en", { persist: false }));
  });
  afterEach(() => {
    localStorage.clear();
    act(() => setLocale("en", { persist: false }));
  });

  it("useT re-renders subscribers when setLocale is called", () => {
    render(React.createElement(Probe));
    expect(screen.getByRole("heading")).toHaveTextContent(en.nav.home);
    act(() => setLocale("te"));
    expect(screen.getByRole("heading")).toHaveTextContent(te.nav.home);
    act(() => setLocale("mr"));
    expect(screen.getByRole("heading")).toHaveTextContent(mr.nav.home);
  });

  it("persists to localStorage and stamps <html lang>", () => {
    setLocale("kn");
    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBe("kn");
    expect(document.documentElement.lang).toBe("kn");
    setLocale("hi", { persist: false });
    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBe("kn");
    expect(document.documentElement.lang).toBe("hi");
  });

  it("restores the persisted locale on boot and ignores junk", () => {
    localStorage.setItem(LOCALE_STORAGE_KEY, "te");
    expect(initLocaleFromStorage()).toBe("te");
    expect(document.documentElement.lang).toBe("te");
    localStorage.setItem(LOCALE_STORAGE_KEY, "xx");
    act(() => setLocale("en", { persist: false }));
    expect(initLocaleFromStorage()).toBe("en");
  });

  it("survives a throwing localStorage", () => {
    const original = Storage.prototype.setItem;
    Storage.prototype.setItem = () => {
      throw new Error("blocked");
    };
    try {
      setLocale("mr");
      expect(getLocale()).toBe("mr");
      expect(document.documentElement.lang).toBe("mr");
    } finally {
      Storage.prototype.setItem = original;
    }
  });

  it("the pre-hydration init script stamps lang from storage", () => {
    localStorage.setItem(LOCALE_STORAGE_KEY, "kn");
    new Function(localeInitScript)();
    expect(document.documentElement.lang).toBe("kn");
    localStorage.setItem(LOCALE_STORAGE_KEY, "fr");
    new Function(localeInitScript)();
    expect(document.documentElement.lang).toBe("en");
  });
});
