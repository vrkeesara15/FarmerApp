"use client";

import { useT } from "@/lib/i18n-client";

/** Keyboard "skip to content" link (WCAG AA); localised live like the rest of the shell. */
export function SkipLink() {
  const t = useT();
  return (
    <a
      href="#main"
      className="sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-50 focus:rounded-input focus:bg-surface focus:px-3 focus:py-2"
    >
      {t("app.skipToContent")}
    </a>
  );
}
