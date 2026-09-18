import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { PlaceholderPage } from "../PlaceholderPage";

export const metadata: Metadata = { title: t("products.title") };

/** C50 */
export default function Page() {
  return <PlaceholderPage screenId="C50" titleKey="products.title" emptyKey="products.empty" />;
}
