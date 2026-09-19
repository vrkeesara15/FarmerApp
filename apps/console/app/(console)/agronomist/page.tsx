import type { Metadata } from "next";
import { ReviewQueue } from "@/components/agronomist/ReviewQueue";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("queue.title") };

/** C60 Agronomist review queue (WC-006, DX-006). */
export default function Page() {
  return <ReviewQueue />;
}
