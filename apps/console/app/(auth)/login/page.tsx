import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { LoginForm } from "./LoginForm";
import { LoginHeader } from "./LoginHeader";

export const metadata: Metadata = { title: t("login.title") };

/** C01 Login — phone + OTP. */
export default function LoginPage() {
  return (
    <main
      id="main"
      className="flex min-h-screen items-center justify-center bg-background p-screen"
    >
      <div className="w-full max-w-md rounded-sheet border border-border bg-surface p-8">
        <LoginHeader />
        <LoginForm />
      </div>
    </main>
  );
}
