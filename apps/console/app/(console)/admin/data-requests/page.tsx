import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { DataRequestsView } from "./_components/DataRequestsView";

export const metadata: Metadata = { title: t("dataRequests.title") };

/** C104 Data-principal requests (NF-013). */
export default function Page() {
  return <DataRequestsView />;
}
