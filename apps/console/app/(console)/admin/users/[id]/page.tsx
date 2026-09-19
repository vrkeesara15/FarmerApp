import type { Metadata } from "next";
import { UserDetailView } from "@/components/admin/UserDetailView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("users.detailTitle") };

/** C101 user detail: role, assignment, devices, forced logout (WC-011). */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <UserDetailView id={decodeURIComponent(id)} />;
}
