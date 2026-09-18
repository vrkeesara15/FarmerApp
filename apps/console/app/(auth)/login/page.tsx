import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { LoginForm } from "./LoginForm";

export const metadata: Metadata = { title: t("login.title") };

/** C01 Login — phone + OTP. */
export default function LoginPage() {
  return (
    <main
      id="main"
      className="flex min-h-screen items-center justify-center bg-background p-screen"
    >
      <div className="w-full max-w-md rounded-sheet border border-border bg-surface p-8">
        <div className="mb-6 flex flex-col gap-1">
          <span className="text-small font-semibold uppercase tracking-wide text-primary">
            {t("app.name")}
          </span>
          <h1 className="text-title">{t("login.title")}</h1>
          <p className="text-body text-text-secondary">{t("login.subtitle")}</p>
        </div>
        <LoginForm />
      </div>
    </main>
  );
}
