import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { PlaceholderPage } from "../PlaceholderPage";

export const metadata: Metadata = { title: t("settings.title") };

/** C102 */
export default function Page() {
  return <PlaceholderPage screenId="C102" titleKey="settings.title" emptyKey="settings.empty" />;
}
