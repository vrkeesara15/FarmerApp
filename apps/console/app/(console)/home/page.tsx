import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { OwnerHomeView } from "./OwnerHomeView";

export const metadata: Metadata = { title: t("home.title") };

/** C10 Owner home (WC-001 / AN-001). Suspense: the view reads the URL filters (AN-011). */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <OwnerHomeView />
    </Suspense>
  );
}
