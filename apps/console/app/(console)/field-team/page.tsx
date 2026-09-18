import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { PlaceholderPage } from "../PlaceholderPage";

export const metadata: Metadata = { title: t("fieldTeam.title") };

/** C20 */
export default function Page() {
  return <PlaceholderPage screenId="C20" titleKey="fieldTeam.title" emptyKey="fieldTeam.empty" />;
}
