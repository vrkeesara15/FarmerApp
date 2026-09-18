/**
 * Minimal typed i18n helper. All UI strings live in messages/<locale>.json; en.json is the
 * source of truth and the type. Other locales are partial and fall back to English per key.
 *
 *   t("login.title")                  -> "Sign in to the console"
 *   t("login.otpSentTo", { phone })   -> "We sent a code to +91 98…"
 */
import en from "@/messages/en.json";
import te from "@/messages/te.json";
import kn from "@/messages/kn.json";
import hi from "@/messages/hi.json";
import mr from "@/messages/mr.json";

export const LOCALES = ["en", "te", "kn", "hi", "mr"] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "en";

type Messages = typeof en;
type Leaves<T, P extends string = ""> = {
  [K in keyof T & string]: T[K] extends string ? `${P}${K}` : Leaves<T[K], `${P}${K}.`>;
}[keyof T & string];

export type MessageKey = Leaves<Messages>;
export type Params = Record<string, string | number>;

type Dict = { [k: string]: string | Dict };
const catalogs: Record<Locale, Dict> = { en, te, kn, hi, mr };

let currentLocale: Locale = DEFAULT_LOCALE;

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && (LOCALES as readonly string[]).includes(value);
}

export function setLocale(locale: Locale): void {
  currentLocale = locale;
}

export function getLocale(): Locale {
  return currentLocale;
}

function lookup(dict: Dict, key: string): string | undefined {
  let node: string | Dict | undefined = dict;
  for (const part of key.split(".")) {
    if (typeof node !== "object" || node === null) return undefined;
    node = node[part];
  }
  return typeof node === "string" ? node : undefined;
}

export function interpolate(template: string, params?: Params): string {
  if (!params) return template;
  return template.replace(/\{(\w+)\}/g, (_, name: string) =>
    name in params ? String(params[name]) : `{${name}}`,
  );
}

/** Translate a message key in the given (or current) locale, falling back to English. */
export function t(key: MessageKey, params?: Params, locale: Locale = currentLocale): string {
  const message = lookup(catalogs[locale], key) ?? lookup(catalogs.en, key) ?? key;
  return interpolate(message, params);
}

/** Script-aware font class for a locale (Tailwind families map to Noto Sans variants). */
export function fontClassFor(locale: Locale): string {
  switch (locale) {
    case "te":
      return "font-telugu";
    case "kn":
      return "font-kannada";
    case "hi":
    case "mr":
      return "font-devanagari";
    default:
      return "font-sans";
  }
}
