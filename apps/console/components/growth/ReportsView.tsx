"use client";

/**
 * C100 reports and scheduled exports (WC-013). Three tabs:
 *
 * - Run an export: any resource the caller may export, with the AN-011 filters currently in the
 *   URL, behind step-up (SEC-028) and audited.
 * - Past exports: the caller's own exports with their signed links (15 minutes).
 * - Scheduled reports: resource, filters, recipients and the cron expression — shown in IST with
 *   a human-readable summary (`cronSummary()`, unit-tested).
 */
import * as React from "react";
import { Download, Play, Plus, ShieldCheck, Trash2 } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Dialog } from "@/components/ds/Dialog";
import { Tabs } from "@/components/ds/Tabs";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/analytics/Page";
import { QueryError, RoleGate, SessionGate, TextAreaField } from "@/components/admin/common";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "@/components/admin/StepUp";
import {
  CRON_PRESETS,
  DEFAULT_CRON,
  EXPORT_ROLES,
  SCHEDULE_ROLES,
  cronSummary,
  formatBytes,
  parseRecipients,
  validateSchedule,
  type ExportFormat,
  type ExportJob,
  type ReportSchedule,
} from "@/lib/exports";
import { formatDateTimeIst, formatNumber } from "@/lib/format";
import {
  useCreateSchedule,
  useDeleteSchedule,
  useExportJobs,
  useExportResources,
  useReportSchedules,
  useRunExport,
  useUpdateSchedule,
} from "@/lib/hooks/growth";
import { useAnalyticsFilters, useSearchParam } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { Choice, Note, TextField } from "./common";

export function ReportsView() {
  return (
    <div className="flex flex-col gap-4" data-screen="C100">
      <SessionGate>
        <RoleGate roles={EXPORT_ROLES}>
          <StepUpProvider>
            <Reports />
          </StepUpProvider>
        </RoleGate>
      </SessionGate>
    </div>
  );
}

const resourceLabel = (t: ReturnType<typeof useT>, name: string): string => {
  const known = [
    "farmers",
    "orders",
    "payments",
    "visits",
    "flags",
    "stock",
    "audit_logs",
    "consent_records",
    "tally",
    "tally_xml",
    "zoho",
  ];
  return known.includes(name) ? t(`reports.resource.${name}` as "reports.resource.orders") : name;
};

function Reports() {
  const t = useT();
  const [tab, setTab] = useSearchParam("tab");
  return (
    <>
      <PageHeader title={t("reports.title")} subtitle={t("reports.subtitle")} />
      <Tabs
        label={t("reports.title")}
        value={tab === "history" || tab === "schedules" ? tab : "run"}
        onValueChange={(v) => setTab(v === "run" ? undefined : v)}
        items={[
          { value: "run", label: t("reports.tab.run"), content: <RunTab /> },
          { value: "history", label: t("reports.tab.history"), content: <HistoryTab /> },
          { value: "schedules", label: t("reports.tab.schedules"), content: <SchedulesTab /> },
        ]}
      />
    </>
  );
}

// ---- run an export ---------------------------------------------------------------------------

function RunTab() {
  const t = useT();
  const stepUp = useStepUp();
  const resources = useExportResources();
  const run = useRunExport();
  const { apiFilters } = useAnalyticsFilters();
  const [resource, setResource] = React.useState("");
  const [format, setFormat] = React.useState<ExportFormat>("csv");
  const [error, setError] = React.useState<string | undefined>();

  const items = React.useMemo(() => resources.data?.items ?? [], [resources.data]);
  const chosen = items.find((r) => r.name === resource) ?? items[0];
  React.useEffect(() => {
    if (!resource && items.length > 0) setResource(items[0]!.name);
  }, [resource, items]);
  React.useEffect(() => {
    if (chosen && !chosen.formats.includes(format)) setFormat(chosen.formats[0] ?? "csv");
  }, [chosen, format]);

  const filters = React.useMemo(
    () => Object.fromEntries(Object.entries(apiFilters).filter(([, v]) => v !== undefined)),
    [apiFilters],
  );

  const onRun = () => {
    if (!chosen) return;
    setError(undefined);
    void stepUp
      .run((headers) => run.mutateAsync({ resource: chosen.name, filters, format, headers }))
      .then(() => toast.success(t("reports.toast.exported")))
      .catch((err: unknown) => {
        if (isStepUpCancelled(err)) return;
        setError(problemMessage(err, t));
      });
  };

  return (
    <div className="flex flex-col gap-3 pt-3" data-testid="run-tab">
      {resources.error ? (
        <QueryError error={resources.error} onRetry={() => void resources.refetch()} />
      ) : (
        <>
          <div className="flex flex-wrap items-end gap-3">
            <Choice
              id="export-resource"
              label={t("reports.run.resource")}
              value={resource}
              options={items.map((r) => ({ value: r.name, label: resourceLabel(t, r.name) }))}
              onChange={(v) => setResource(v)}
            />
            <Choice
              id="export-format"
              label={t("reports.run.format")}
              value={format}
              options={(chosen?.formats ?? ["csv"]).map((f) => ({
                value: f,
                label: t(`reports.format.${f}`),
              }))}
              onChange={(v) => setFormat((v || "csv") as ExportFormat)}
            />
            <AppButton
              onClick={onRun}
              loading={run.isPending}
              disabled={!chosen}
              data-testid="run-export"
            >
              <Play className="size-4" aria-hidden="true" />
              {t("reports.run.button")}
            </AppButton>
          </div>
          <p className="text-small text-text-secondary" data-testid="export-filters">
            {Object.keys(filters).length === 0
              ? t("reports.run.noFilters")
              : `${t("reports.run.filters")}: ${Object.entries(filters)
                  .map(([k, v]) => `${k}=${String(v)}`)
                  .join(", ")}`}
          </p>
          {chosen ? (
            <p className="text-small text-text-muted">
              {t("reports.run.columns", { columns: chosen.columns.join(", ") })}
            </p>
          ) : null}
          <Note icon={<ShieldCheck className="size-4" aria-hidden="true" />}>
            {t("reports.run.help")} {t("reports.run.limit")}
          </Note>
          {error ? (
            <p className="text-body text-danger" role="alert" data-testid="export-error">
              {error}
            </p>
          ) : null}
        </>
      )}
    </div>
  );
}

// ---- past exports ------------------------------------------------------------------------------

function HistoryTab() {
  const t = useT();
  const jobs = useExportJobs();
  const na = t("common.none");

  const columns: ReadonlyArray<DataTableColumn<ExportJob>> = [
    {
      id: "resource",
      header: t("reports.history.column.resource"),
      cell: (j) => resourceLabel(t, j.resource),
    },
    {
      id: "format",
      header: t("reports.history.column.format"),
      cell: (j) => t(`reports.format.${j.format}` as "reports.format.csv"),
    },
    {
      id: "rows",
      header: t("reports.history.column.rows"),
      numeric: true,
      accessor: (j) => j.rows,
      cell: (j) => formatNumber(j.rows),
    },
    {
      id: "size",
      header: t("reports.history.column.size"),
      numeric: true,
      cell: (j) => formatBytes(j.size_bytes),
    },
    {
      id: "created",
      header: t("reports.history.column.created"),
      accessor: (j) => j.created_at,
      cell: (j) => formatDateTimeIst(j.created_at),
    },
    {
      id: "link",
      header: t("reports.history.column.link"),
      cell: (j) =>
        j.url ? (
          <a
            href={j.url}
            download={j.filename}
            className="inline-flex items-center gap-1 text-primary underline"
            data-testid="export-link"
          >
            <Download className="size-4" aria-hidden="true" />
            {t("reports.history.download")}
          </a>
        ) : (
          na
        ),
    },
  ];

  return (
    <div className="flex flex-col gap-3 pt-3" data-testid="history-tab">
      <p className="text-small text-text-muted">{t("reports.history.signed")}</p>
      {jobs.error ? (
        <QueryError error={jobs.error} onRetry={() => void jobs.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={jobs.data?.items ?? []}
          rowKey={(j) => j.id}
          loading={jobs.isLoading}
          caption={t("reports.history.title")}
          emptyTitle={t("reports.history.emptyTitle")}
          emptyHelp={t("reports.history.emptyHelp")}
        />
      )}
    </div>
  );
}

// ---- scheduled reports ---------------------------------------------------------------------------

interface ScheduleDraft {
  id: string | null;
  name: string;
  resource: string;
  format: ExportFormat;
  recipients: string;
  cron: string;
  active: boolean;
}

const emptyDraft = (resource: string): ScheduleDraft => ({
  id: null,
  name: "",
  resource,
  format: "csv",
  recipients: "",
  cron: DEFAULT_CRON,
  active: true,
});

function SchedulesTab() {
  const t = useT();
  const { role } = useSession();
  const stepUp = useStepUp();
  const schedules = useReportSchedules();
  const resources = useExportResources();
  const create = useCreateSchedule();
  const update = useUpdateSchedule();
  const remove = useDeleteSchedule();
  const [draft, setDraft] = React.useState<ScheduleDraft | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState<ReportSchedule | null>(null);
  const [error, setError] = React.useState<string | undefined>();
  const canWrite = !!role && SCHEDULE_ROLES.includes(role);
  const resourceNames = (resources.data?.items ?? []).map((r) => r.name);

  const issues = draft
    ? validateSchedule({
        name: draft.name,
        resource: draft.resource,
        recipients: parseRecipients(draft.recipients),
        cron: draft.cron,
      })
    : [];

  const columns: ReadonlyArray<DataTableColumn<ReportSchedule>> = [
    {
      id: "name",
      header: t("reports.schedules.column.name"),
      accessor: (s) => s.name,
      cell: (s) => <span className="font-semibold">{s.name}</span>,
    },
    {
      id: "resource",
      header: t("reports.schedules.column.resource"),
      cell: (s) => resourceLabel(t, s.resource),
    },
    {
      id: "recipients",
      header: t("reports.schedules.column.recipients"),
      cell: (s) => s.recipients.join(", "),
    },
    {
      id: "cron",
      header: t("reports.schedules.column.cron"),
      cell: (s) => <span data-testid="cron-summary">{cronSummary(s.cron, t)}</span>,
    },
    {
      id: "next",
      header: t("reports.schedules.column.next"),
      cell: (s) => (s.next_run_at ? formatDateTimeIst(s.next_run_at) : t("common.none")),
    },
    {
      id: "active",
      header: t("reports.schedules.column.active"),
      cell: (s) => (
        <Badge variant={s.active ? "success" : "neutral"}>
          {s.active ? t("reports.schedules.active") : t("reports.schedules.paused")}
        </Badge>
      ),
    },
    {
      id: "actions",
      header: t("reports.schedules.edit"),
      cell: (s) =>
        canWrite ? (
          <span className="flex flex-wrap gap-2">
            <AppButton
              variant="tertiary"
              onClick={() => {
                setError(undefined);
                setDraft({
                  id: s.id,
                  name: s.name,
                  resource: s.resource,
                  format: s.format as ExportFormat,
                  recipients: s.recipients.join("\n"),
                  cron: s.cron,
                  active: s.active,
                });
              }}
            >
              {t("reports.schedules.edit")}
            </AppButton>
            <AppButton variant="tertiary" onClick={() => setConfirmDelete(s)}>
              <Trash2 className="size-4" aria-hidden="true" />
              {t("reports.schedules.delete")}
            </AppButton>
          </span>
        ) : (
          t("common.none")
        ),
    },
  ];

  const onSave = () => {
    if (!draft || issues.length > 0) return;
    setError(undefined);
    const body = {
      name: draft.name.trim(),
      resource: draft.resource,
      format: draft.format,
      filters: {},
      recipients: parseRecipients(draft.recipients),
      cron: draft.cron,
      active: draft.active,
    };
    void stepUp
      .run((headers) =>
        draft.id
          ? update.mutateAsync({ id: draft.id, body, headers })
          : create.mutateAsync({ body, headers }),
      )
      .then(() => {
        toast.success(t("reports.toast.scheduleSaved"));
        setDraft(null);
      })
      .catch((err: unknown) => {
        if (isStepUpCancelled(err)) return;
        setError(problemMessage(err, t));
      });
  };

  return (
    <div className="flex flex-col gap-3 pt-3" data-testid="schedules-tab">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-small text-text-muted">{t("reports.schedules.cronHelp")}</p>
        {canWrite ? (
          <AppButton
            onClick={() => {
              setError(undefined);
              setDraft(emptyDraft(resourceNames[0] ?? "orders"));
            }}
            data-testid="new-schedule"
          >
            <Plus className="size-4" aria-hidden="true" />
            {t("reports.schedules.add")}
          </AppButton>
        ) : null}
      </div>
      {schedules.error ? (
        <QueryError error={schedules.error} onRetry={() => void schedules.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={schedules.data?.items ?? []}
          rowKey={(s) => s.id}
          loading={schedules.isLoading}
          caption={t("reports.schedules.title")}
          emptyTitle={t("reports.schedules.emptyTitle")}
          emptyHelp={t("reports.schedules.emptyHelp")}
        />
      )}

      <Dialog
        open={!!draft}
        onOpenChange={(o) => {
          if (!o) setDraft(null);
        }}
        title={draft?.id ? t("reports.schedules.edit") : t("reports.schedules.add")}
        description={t("reports.schedules.stepUpHelp")}
        confirmLabel={t("reports.schedules.save")}
        loading={create.isPending || update.isPending}
        error={error}
        onConfirm={onSave}
      >
        {draft ? (
          <div className="flex flex-col gap-3">
            <TextField
              id="schedule-name"
              label={t("reports.schedules.name")}
              value={draft.name}
              onChange={(name) => setDraft({ ...draft, name })}
            />
            <Choice
              id="schedule-resource"
              label={t("reports.run.resource")}
              value={draft.resource}
              options={resourceNames.map((r) => ({ value: r, label: resourceLabel(t, r) }))}
              onChange={(resource) => setDraft({ ...draft, resource: resource || draft.resource })}
            />
            <TextAreaField
              label={t("reports.schedules.recipients")}
              value={draft.recipients}
              onChange={(e) => setDraft({ ...draft, recipients: e.target.value })}
              rows={3}
            />
            <p className="text-small text-text-muted">{t("reports.schedules.recipientsHelp")}</p>
            <Choice
              id="schedule-preset"
              label={t("reports.preset.label")}
              value={CRON_PRESETS.some((p) => p.cron === draft.cron) ? draft.cron : ""}
              includeAll
              options={CRON_PRESETS.map((p) => ({ value: p.cron, label: t(p.labelKey) }))}
              onChange={(cron) => setDraft({ ...draft, cron: cron || draft.cron })}
            />
            <TextField
              id="schedule-cron"
              label={t("reports.schedules.cron")}
              value={draft.cron}
              onChange={(cron) => setDraft({ ...draft, cron })}
            />
            <p className="text-body" data-testid="cron-preview">
              {cronSummary(draft.cron, t)}
            </p>
            {issues.length > 0 ? (
              <ul className="list-inside list-disc text-small text-danger" role="alert">
                {issues.map((i) => (
                  <li key={i.code}>
                    {t(`reports.scheduleError.${i.code}` as "reports.scheduleError.cronInvalid")}
                  </li>
                ))}
              </ul>
            ) : null}
          </div>
        ) : null}
      </Dialog>

      <Dialog
        open={!!confirmDelete}
        onOpenChange={(o) => {
          if (!o) setConfirmDelete(null);
        }}
        title={t("reports.schedules.deleteTitle")}
        description={t("reports.schedules.deleteHelp")}
        confirmLabel={t("reports.schedules.delete")}
        destructive
        loading={remove.isPending}
        error={error}
        onConfirm={() => {
          if (!confirmDelete) return;
          setError(undefined);
          void stepUp
            .run((headers) => remove.mutateAsync({ id: confirmDelete.id, headers }))
            .then(() => {
              toast.success(t("reports.toast.scheduleDeleted"));
              setConfirmDelete(null);
            })
            .catch((err: unknown) => {
              if (isStepUpCancelled(err)) return;
              setError(problemMessage(err, t));
            });
        }}
      />
    </div>
  );
}
