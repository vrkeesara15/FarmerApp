import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { CropHealthView } from "@/components/growth/CropHealthView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("cropHealth.title") };

/** AN-006 Crop health map (district level only, AN-014). */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <CropHealthView />
    </Suspense>
  );
}
