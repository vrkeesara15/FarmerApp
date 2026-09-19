import type { Metadata } from "next";
import { SettingsView } from "@/components/admin/SettingsView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("settings.title") };

/** C102 Settings with the branding preview of both apps (WC-012). */
export default function Page() {
  return <SettingsView />;
}
