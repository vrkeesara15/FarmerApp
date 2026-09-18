import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { ProductsView } from "./ProductsView";

export const metadata: Metadata = { title: t("products.title") };

/** C50 Product master (WC-005). */
export default function Page() {
  return <ProductsView />;
}
