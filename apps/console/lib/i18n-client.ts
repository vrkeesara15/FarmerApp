/**
 * React bindings for the locale store in lib/i18n.ts. Kept in a separate module because
 * React hooks may only be imported from client components; lib/i18n.ts itself is also
 * used by server components and metadata.
 */
import { useCallback, useSyncExternalStore } from "react";
import { DEFAULT_LOCALE, getLocale, subscribeLocale, t, type Locale, type TFunction } from "./i18n";

/** The current locale; subscribes the component so it re-renders on `setLocale`. */
export function useLocale(): Locale {
  return useSyncExternalStore(subscribeLocale, getLocale, () => DEFAULT_LOCALE);
}

/** `t` bound to the current locale; use in client components instead of the bare `t`. */
export function useT(): TFunction {
  const locale = useLocale();
  return useCallback<TFunction>((key, params) => t(key, params, locale), [locale]);
}
