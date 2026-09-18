import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { PricesView } from "./PricesView";

export const metadata: Metadata = { title: t("prices.title") };

/** C52 Price lists (WC-005). */
export default function Page() {
  return <PricesView />;
}
