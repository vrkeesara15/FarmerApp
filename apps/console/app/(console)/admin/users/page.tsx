import type { Metadata } from "next";
import { UsersView } from "@/components/admin/UsersView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("users.title") };

/** C101 Users and roles (WC-011). */
export default function Page() {
  return <UsersView />;
}
