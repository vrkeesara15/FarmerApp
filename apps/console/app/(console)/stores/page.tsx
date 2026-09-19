import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { StoresView } from "./StoresView";

export const metadata: Metadata = { title: t("stores.title") };

/** C40 Stores (WC-004). */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <StoresView />
    </Suspense>
  );
}
