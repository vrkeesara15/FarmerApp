import type { Metadata } from "next";
import { FlagDetailView } from "@/components/flags/FlagDetailView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("flagDetail.title") };

/** C71 Flag detail (WC-010, VA-002). */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <FlagDetailView id={decodeURIComponent(id)} />;
}
