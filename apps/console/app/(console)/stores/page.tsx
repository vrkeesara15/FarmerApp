import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { PlaceholderPage } from "../PlaceholderPage";

export const metadata: Metadata = { title: t("stores.title") };

/** C40 */
export default function Page() {
  return <PlaceholderPage screenId="C40" titleKey="stores.title" emptyKey="stores.empty" />;
}
