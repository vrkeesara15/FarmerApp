import type { Metadata } from "next";
import { AuditView } from "@/components/admin/AuditView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("audit.title") };

/** C103 Audit log viewer (WC-103). */
export default function Page() {
  return <AuditView />;
}
