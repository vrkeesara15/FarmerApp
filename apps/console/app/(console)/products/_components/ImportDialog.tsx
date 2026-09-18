"use client";

import * as React from "react";
import { Dialog } from "@/components/ds/Dialog";
import { toast } from "@/components/ds/Toasts";
import type { ImportKind, ImportReport } from "@/lib/catalog";
import { useImportCsv } from "@/lib/hooks/catalog";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";

/**
 * CSV import (WC-005, WC-013 builds on it): the file is always checked first with a dry run
 * that returns a row-level report; "Apply" re-posts the same text with dry_run=false and is
 * only offered when the dry run found no errors.
 */
export function ImportDialog({
  open,
  onOpenChange,
  kind,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  kind: ImportKind;
}) {
  const t = useT();
  const mutation = useImportCsv();
  const [csv, setCsv] = React.useState<string | null>(null);
  const [fileName, setFileName] = React.useState("");
  const [report, setReport] = React.useState<ImportReport | null>(null);
  const [error, setError] = React.useState<string>();
  const inputId = React.useId();

  React.useEffect(() => {
    if (open) {
      setCsv(null);
      setFileName("");
      setReport(null);
      setError(undefined);
    }
  }, [open]);

  const run = async (text: string, dryRun: boolean) => {
    setError(undefined);
    try {
      const res = await mutation.mutateAsync({ kind, csv: text, dryRun });
      setReport(res);
      if (res.applied) {
        toast.success(t("import.appliedToast", { n: res.created + res.updated }));
        onOpenChange(false);
      }
    } catch (err) {
      setError(problemMessage(err, t));
    }
  };

  const onFile = async (file: File | undefined) => {
    if (!file) return;
    const text = await file.text();
    setCsv(text);
    setFileName(file.name);
    await run(text, true);
  };

  const canApply = !!csv && !!report && report.dry_run && report.errors.length === 0;

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={kind === "products" ? t("import.titleProducts") : t("import.titleClaims")}
      description={kind === "products" ? t("import.helpProducts") : t("import.helpClaims")}
      confirmLabel={t("import.apply")}
      onConfirm={canApply && csv ? () => void run(csv, false) : undefined}
      loading={mutation.isPending}
      error={error}
      className="max-w-2xl"
    >
      <div className="flex flex-col gap-3" data-testid="import-dialog">
        <label htmlFor={inputId} className="text-small font-semibold text-text-secondary">
          {t("import.file")}
        </label>
        <input
          id={inputId}
          type="file"
          accept=".csv,text/csv"
          data-testid="import-file"
          onChange={(e) => void onFile(e.target.files?.[0])}
          className="text-body"
        />
        {fileName ? <p className="text-small text-text-muted">{fileName}</p> : null}
        {report ? (
          <div className="flex flex-col gap-2" data-testid="import-report">
            <p className="tnum text-body">
              {t("import.summary", {
                total: report.rows_total,
                ok: report.rows_ok,
                created: report.created,
                updated: report.updated,
              })}
            </p>
            {report.errors.length === 0 ? (
              <p className="text-body text-success">{t("import.noErrors")}</p>
            ) : (
              <div className="max-h-64 overflow-auto rounded-card border border-border">
                <table className="w-full text-small">
                  <thead>
                    <tr className="bg-background text-left">
                      <th className="px-2 py-1">{t("import.row")}</th>
                      <th className="px-2 py-1">{t("import.column")}</th>
                      <th className="px-2 py-1">{t("import.problem")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {report.errors.map((e, i) => (
                      <tr
                        key={`${e.row}-${e.column}-${i}`}
                        className="border-t border-border"
                        data-testid="import-error-row"
                      >
                        <td className="tnum px-2 py-1">{e.row}</td>
                        <td className="px-2 py-1">{e.column ?? t("common.none")}</td>
                        <td className="px-2 py-1">{e.message}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        ) : null}
      </div>
    </Dialog>
  );
}
