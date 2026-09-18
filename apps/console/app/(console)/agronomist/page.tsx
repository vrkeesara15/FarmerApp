import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { PlaceholderPage } from "../PlaceholderPage";

export const metadata: Metadata = { title: t("agronomist.title") };

/** C60 */
export default function Page() {
  return <PlaceholderPage screenId="C60" titleKey="agronomist.title" emptyKey="agronomist.empty" />;
}
