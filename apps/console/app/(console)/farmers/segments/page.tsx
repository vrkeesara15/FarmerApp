import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { SegmentsView } from "@/components/growth/SegmentsView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("segments.title") };

/** C32 Farmer segments builder (AN-004, WC-008 segment rules with the consented count). */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <SegmentsView />
    </Suspense>
  );
}
