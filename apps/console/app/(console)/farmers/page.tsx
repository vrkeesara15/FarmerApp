import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { FarmersView } from "./FarmersView";

export const metadata: Metadata = { title: t("farmers.title") };

/** C30 Farmers directory (WC-003). */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <FarmersView />
    </Suspense>
  );
}
