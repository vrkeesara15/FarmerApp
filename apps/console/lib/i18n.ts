/**
 * Minimal typed i18n with a tiny reactive locale store (FA-004).
 *
 * All UI strings live in messages/<locale>.json; en.json is the source of truth and the
 * type. Every other launch language carries every key (lib/i18n.test.ts enforces it); a
 * missing key still falls back to English per key so a partial catalogue never crashes.
 *
 *   t("login.title")                  -> "Sign in to the console"      (server components, metadata)
 *   const t = useT(); t("nav.home")   -> re-renders when the locale changes (client components;
 *                                        hooks live in lib/i18n-client.ts)
 *
 * The chosen locale is persisted in localStorage (best effort, try/catch) and applied to
 * `<html lang>`; app/globals.css maps `:lang(te|kn|hi|mr)` to the Noto script fonts, so
 * switching the language re-fonts the page without a reload.
 */
import en from "@/messages/en.json";
import te from "@/messages/te.json";
import kn from "@/messages/kn.json";
import hi from "@/messages/hi.json";
import mr from "@/messages/mr.json";

export const LOCALES = ["en", "te", "kn", "hi", "mr"] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "en";
/** Per-browser preference; the account-level default arrives with WC-012 tenant settings. */
export const LOCALE_STORAGE_KEY = "farmerapp.console.locale";

type Messages = typeof en;
type Leaves<T, P extends string = ""> = {
  [K in keyof T & string]: T[K] extends string ? `${P}${K}` : Leaves<T[K], `${P}${K}.`>;
}[keyof T & string];

export type MessageKey = Leaves<Messages>;
export type Params = Record<string, string | number>;
export type TFunction = (key: MessageKey, params?: Params) => string;

/** Language menu entries. Script names are literal (never translated) so anyone can find theirs. */
export const LOCALE_OPTIONS: ReadonlyArray<{
  locale: Locale;
  nativeName: string;
  nameKey: MessageKey;
}> = [
  { locale: "en", nativeName: "English", nameKey: "language.en" },
  { locale: "te", nativeName: "తెలుగు", nameKey: "language.te" },
  { locale: "kn", nativeName: "ಕನ್ನಡ", nameKey: "language.kn" },
  { locale: "hi", nativeName: "हिन्दी", nameKey: "language.hi" },
  { locale: "mr", nativeName: "मराठी", nameKey: "language.mr" },
];

type Dict = { [k: string]: string | Dict };
const catalogs: Record<Locale, Dict> = { en, te, kn, hi, mr };

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && (LOCALES as readonly string[]).includes(value);
}

export function readStoredLocale(): Locale | null {
  try {
    const v = window.localStorage.getItem(LOCALE_STORAGE_KEY);
    return isLocale(v) ? v : null;
  } catch {
    return null;
  }
}

export function storeLocale(locale: Locale): void {
  try {
    window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  } catch {
    /* storage unavailable (private mode, blocked) — the locale still applies for this page */
  }
}

/** `<html lang>` drives the script font and line height (globals.css) and screen readers. */
export function applyLocaleToDocument(locale: Locale): void {
  if (typeof document === "undefined") return;
  document.documentElement.lang = locale;
}

// ---- store -------------------------------------------------------------------------------
// On the client the store starts from the persisted value; the server (and hydration, via
// getServerSnapshot) always renders English, then React re-renders subscribers once.
let currentLocale: Locale =
  typeof window === "undefined" ? DEFAULT_LOCALE : (readStoredLocale() ?? DEFAULT_LOCALE);
const listeners = new Set<() => void>();

export function getLocale(): Locale {
  return currentLocale;
}

export function subscribeLocale(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** Switch the language for the whole app without a reload; persisted unless `persist: false`. */
export function setLocale(locale: Locale, options: { persist?: boolean } = {}): void {
  if (options.persist !== false) storeLocale(locale);
  applyLocaleToDocument(locale);
  if (locale === currentLocale) return;
  currentLocale = locale;
  for (const listener of listeners) listener();
}

/** Called once on the client after hydration: re-reads storage and stamps `<html lang>`. */
export function initLocaleFromStorage(): Locale {
  setLocale(readStoredLocale() ?? currentLocale, { persist: false });
  return currentLocale;
}

/** Inline script (runs before hydration) so the first paint already has the right lang/font. */
export const localeInitScript = `(function(){var d="en";try{var l=localStorage.getItem(${JSON.stringify(
  LOCALE_STORAGE_KEY,
)});if(${JSON.stringify([...LOCALES])}.indexOf(l)<0){l=d}document.documentElement.lang=l}catch(e){document.documentElement.lang=d}})();`;

// ---- lookup ------------------------------------------------------------------------------
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
