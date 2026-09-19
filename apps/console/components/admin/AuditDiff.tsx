"use client";

/** C103 before / after of one audit row, field by field, changed fields first and highlighted. */
import { auditDiff, diffValue, type AuditLog } from "@/lib/admin";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export function AuditDiff({ log }: { log: Pick<AuditLog, "before" | "after"> }) {
  const t = useT();
  const rows = auditDiff(log.before, log.after);
  if (!rows.length) return <p className="text-small text-text-muted">{t("audit.diff.none")}</p>;
  const cell = (v: unknown) => {
    const s = diffValue(v);
    return s === undefined ? (
      <span className="text-text-muted">{t("audit.diff.absent")}</span>
    ) : (
      <code className="whitespace-pre-wrap break-all">{s}</code>
    );
  };
  return (
    <table className="w-full table-fixed text-small" data-testid="audit-diff">
      <thead>
        <tr className="text-left text-text-muted">
          <th scope="col" className="w-1/4 py-1 pr-2 font-semibold">
            {t("audit.diff.field")}
          </th>
          <th scope="col" className="py-1 pr-2 font-semibold">
            {t("audit.diff.before")}
          </th>
          <th scope="col" className="py-1 font-semibold">
            {t("audit.diff.after")}
          </th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <tr
            key={r.field}
            data-testid="diff-row"
            data-changed={r.changed ? "true" : "false"}
            className={cn("border-t border-border align-top", !r.changed && "text-text-muted")}
          >
            <th scope="row" className="py-1 pr-2 text-left font-semibold">
              {r.field}
              {r.changed ? <span className="sr-only"> {t("audit.diff.changed")}</span> : null}
            </th>
            <td className={cn("py-1 pr-2", r.changed && "bg-danger-container/60 text-text")}>
              {cell(r.before)}
            </td>
            <td className={cn("py-1", r.changed && "bg-success-container/60 text-text")}>
              {cell(r.after)}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
