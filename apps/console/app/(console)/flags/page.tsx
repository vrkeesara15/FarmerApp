import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { PlaceholderPage } from "../PlaceholderPage";

export const metadata: Metadata = { title: t("flags.title") };

/** C70 */
export default function Page() {
  return <PlaceholderPage screenId="C70" titleKey="flags.title" emptyKey="flags.empty" />;
}
