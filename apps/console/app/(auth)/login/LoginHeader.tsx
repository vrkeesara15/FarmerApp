"use client";

import { useT } from "@/lib/i18n-client";

/** C01 heading block; a client component so it follows the live language switch. */
export function LoginHeader() {
  const t = useT();
  return (
    <div className="mb-6 flex flex-col gap-1">
      <span className="text-small font-semibold uppercase tracking-wide text-primary">
        {t("app.name")}
      </span>
      <h1 className="text-title">{t("login.title")}</h1>
      <p className="text-body text-text-secondary">{t("login.subtitle")}</p>
    </div>
  );
}
