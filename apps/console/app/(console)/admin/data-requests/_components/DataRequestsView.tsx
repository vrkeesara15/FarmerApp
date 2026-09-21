"use client";

/**
 * C104 Data requests (NF-013): the staff queue for data-principal rights under the DPDP Act.
 *
 * Left: every access / correction / erasure / grievance request, closest statutory deadline
 * first, with an overdue badge. Right: the selected request with the actions the API allows —
 * Start, Complete and Reject (both with a resolution note), Apply correction (shows the
 * requested field -> value diff), Run erasure (shows what was erased and what the law makes us
 * keep) and Download export. The two destructive calls are `x-step-up: true`, so they go
 * through the SEC-028 dialog (components/admin/StepUp.tsx) exactly like C101 / C102.
 */
import * as React from "react";
import { Download, Pencil, ShieldAlert } from "lucide-react";
import { AdminSubNav } from "@/components/admin/AdminSubNav";
import {
  Field,
  PageHeader,
  QueryError,
  RoleGate,
  SelectField,
  SessionGate,
  TextAreaField,
} from "@/components/admin/common";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "@/components/admin/StepUp";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Dialog } from "@/components/ds/Dialog";
import { EmptyState } from "@/components/ds/EmptyState";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import { downloadText } from "@/lib/catalog";
import {
  DATA_REQUEST_ROLES,
  DATA_REQUEST_STATUSES,
  DATA_REQUEST_TYPES,
  availableActions,
  correctionRows,
  exportFilename,
  isOverdue,
  sortByDue,
  type ApplyCorrectionResult,
  type DataRequest,
  type DataRequestStatus,
  type DataRequestType,
  type ErasureResult,
} from "@/lib/data-requests";
import { formatDateTimeIst } from "@/lib/format";
import {
  useApplyCorrection,
  useDataRequests,
  useExportData,
  useRunErasure,
  useUpdateDataRequest,
} from "@/lib/hooks/data-requests";
import { useT } from "@/lib/i18n-client";
import type { TFunction } from "@/lib/i18n";
import { problemMessage } from "@/lib/problem-messages";

type T = TFunction;

export function DataRequestsView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C104">
      <PageHeader title={t("dataRequests.title")} subtitle={t("dataRequests.subtitle")} />
      <AdminSubNav />
      <SessionGate>
        <RoleGate roles={DATA_REQUEST_ROLES}>
          <StepUpProvider>
            <Queue />
          </StepUpProvider>
        </RoleGate>
      </SessionGate>
    </div>
  );
}

const STATUS_VARIANT: Record<DataRequestStatus, "warning" | "info" | "success" | "neutral"> = {
  received: "warning",
  in_progress: "info",
  completed: "success",
  rejected: "neutral",
};

function StatusBadge({ status }: { status: DataRequestStatus }) {
  const t = useT();
  return (
    <Badge variant={STATUS_VARIANT[status]} data-testid="request-status" data-status={status}>
      {t(`dataRequests.status.${status}`)}
    </Badge>
  );
}

function OverdueBadge() {
  const t = useT();
  return (
    <Badge variant="danger" data-testid="request-overdue">
      {t("dataRequests.overdue")}
    </Badge>
  );
}

const typeLabel = (t: T, type: DataRequestType): string => t(`dataRequests.type.${type}`);

/** One-line summary of a request: its subject, else the first words of the stated reason. */
function summaryOf(request: DataRequest): string {
  return request.subject ?? request.reason ?? request.id;
}

function Queue() {
  const t = useT();
  const [type, setType] = React.useState<DataRequestType | "">("");
  const [status, setStatus] = React.useState<DataRequestStatus | "">("");
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const requests = useDataRequests({ type, status });

  const rows = React.useMemo(() => sortByDue(requests.data?.items ?? []), [requests.data]);
  // Keep the selection valid when the filters or the data change.
  const selected = rows.find((r) => r.id === selectedId) ?? null;
  React.useEffect(() => {
    if (rows.length && !rows.some((r) => r.id === selectedId)) setSelectedId(rows[0]?.id ?? null);
  }, [rows, selectedId]);

  const columns: DataTableColumn<DataRequest>[] = [
    {
      id: "type",
      header: t("dataRequests.columns.type"),
      sortable: true,
      accessor: (r) => r.type,
      cell: (r) => <span data-testid="request-type">{typeLabel(t, r.type)}</span>,
    },
    {
      id: "summary",
      header: t("dataRequests.columns.summary"),
      cell: (r) => (
        <button
          type="button"
          onClick={() => setSelectedId(r.id)}
          aria-label={t("dataRequests.actions.open", { type: typeLabel(t, r.type) })}
          className="text-left font-semibold text-primary hover:underline"
        >
          {summaryOf(r)}
        </button>
      ),
    },
    {
      id: "status",
      header: t("dataRequests.columns.status"),
      sortable: true,
      accessor: (r) => r.status,
      cell: (r) => <StatusBadge status={r.status} />,
    },
    {
      id: "due",
      header: t("dataRequests.columns.due"),
      sortable: true,
      accessor: (r) => r.due_by,
      cell: (r) => (
        <span className="flex flex-wrap items-center gap-2">
          <span className="tnum">{formatDateTimeIst(r.due_by)}</span>
          {isOverdue(r) ? <OverdueBadge /> : null}
        </span>
      ),
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end gap-3" data-testid="data-request-filters">
        <SelectField
          label={t("dataRequests.columns.type")}
          value={type}
          onChange={(e) => setType(e.target.value as DataRequestType | "")}
          emptyLabel={t("common.all")}
          options={DATA_REQUEST_TYPES.map((v) => ({ value: v, label: typeLabel(t, v) }))}
          className="min-w-44"
          testId="filter-type"
        />
        <SelectField
          label={t("dataRequests.columns.status")}
          value={status}
          onChange={(e) => setStatus(e.target.value as DataRequestStatus | "")}
          emptyLabel={t("common.all")}
          options={DATA_REQUEST_STATUSES.map((v) => ({
            value: v,
            label: t(`dataRequests.status.${v}`),
          }))}
          className="min-w-44"
          testId="filter-status"
        />
      </div>
      {requests.error ? (
        <QueryError error={requests.error} onRetry={() => void requests.refetch()} />
      ) : (
        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_26rem]">
          <DataTable
            columns={columns}
            rows={rows}
            rowKey={(r) => r.id}
            onRowClick={(r) => setSelectedId(r.id)}
            loading={requests.isLoading}
            caption={t("dataRequests.queueCaption")}
            emptyTitle={t("dataRequests.emptyTitle")}
            emptyHelp={t("dataRequests.emptyHelp")}
          />
          {selected ? (
            <RequestDetail key={selected.id} request={selected} />
          ) : (
            <EmptyState
              title={t("dataRequests.selectTitle")}
              help={t("dataRequests.selectHelp")}
              className="h-fit"
            />
          )}
        </div>
      )}
    </div>
  );
}

type NoteAction = "complete" | "reject";

function RequestDetail({ request }: { request: DataRequest }) {
  const t = useT();
  const stepUp = useStepUp();
  const update = useUpdateDataRequest();
  const applyCorrection = useApplyCorrection(stepUp);
  const runErasure = useRunErasure(stepUp);
  const exportData = useExportData();

  const [noteAction, setNoteAction] = React.useState<NoteAction | null>(null);
  const [startOpen, setStartOpen] = React.useState(false);
  const [correctionOpen, setCorrectionOpen] = React.useState(false);
  const [erasureOpen, setErasureOpen] = React.useState(false);
  const [applied, setApplied] = React.useState<ApplyCorrectionResult | null>(null);
  const [erasure, setErasure] = React.useState<ErasureResult | null>(null);
  const [exported, setExported] = React.useState<string | null>(null);
  const [error, setError] = React.useState<string | undefined>();

  const actions = availableActions(request);
  const changes = correctionRows(request);
  const fail = (err: unknown) =>
    setError(isStepUpCancelled(err) ? t("stepUp.cancelled") : problemMessage(err, t));

  const move = (status: DataRequestStatus, note: string | undefined, done: string) => {
    setError(undefined);
    update.mutate(
      { id: request.id, status, note },
      {
        onSuccess: () => {
          toast.success(done);
          setStartOpen(false);
          setNoteAction(null);
        },
        onError: fail,
      },
    );
  };

  const onExport = () => {
    setError(undefined);
    exportData.mutate(request.id, {
      onSuccess: (data) => {
        const text = JSON.stringify(data, null, 2);
        setExported(text);
        downloadText(exportFilename(request.id), text, "application/json");
        toast.success(t("dataRequests.export.done"));
      },
      onError: fail,
    });
  };

  return (
    <aside
      className="flex h-fit flex-col gap-4 rounded-card border border-border bg-surface p-4"
      data-testid="request-detail"
      data-request-id={request.id}
      aria-label={t("dataRequests.actions.open", { type: typeLabel(t, request.type) })}
    >
      <div className="flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-heading font-semibold text-text">{typeLabel(t, request.type)}</h2>
          <StatusBadge status={request.status} />
          {isOverdue(request) ? <OverdueBadge /> : null}
        </div>
        <p className="text-body text-text-secondary">{summaryOf(request)}</p>
      </div>

      <dl className="grid grid-cols-2 gap-3">
        <Field label={t("dataRequests.fields.due")} testId="detail-due">
          <span className="tnum">{formatDateTimeIst(request.due_by)}</span>
        </Field>
        <Field label={t("dataRequests.fields.created")}>
          <span className="tnum">{formatDateTimeIst(request.created_at)}</span>
        </Field>
        <Field label={t("dataRequests.fields.requester")}>{request.user_id}</Field>
        <Field label={t("dataRequests.fields.farmer")}>
          {request.farmer_id ?? t("common.none")}
        </Field>
        {request.reason ? (
          <Field label={t("dataRequests.fields.reason")}>{request.reason}</Field>
        ) : null}
        {request.handled_at ? (
          <Field label={t("dataRequests.fields.handledAt")}>
            <span className="tnum">{formatDateTimeIst(request.handled_at)}</span>
          </Field>
        ) : null}
        {request.resolution_note ? (
          <Field label={t("dataRequests.fields.resolution")} testId="detail-resolution">
            {request.resolution_note}
          </Field>
        ) : null}
      </dl>

      {changes.length ? (
        <CorrectionTable rows={changes} title={t("dataRequests.correction.requested")} />
      ) : null}

      <div className="flex flex-wrap gap-2" data-testid="request-actions">
        {actions.start ? (
          <AppButton onClick={() => setStartOpen(true)}>
            {t("dataRequests.actions.start")}
          </AppButton>
        ) : null}
        {actions.complete ? (
          <AppButton onClick={() => setNoteAction("complete")}>
            {t("dataRequests.actions.complete")}
          </AppButton>
        ) : null}
        {actions.reject ? (
          <AppButton variant="secondary" onClick={() => setNoteAction("reject")}>
            {t("dataRequests.actions.reject")}
          </AppButton>
        ) : null}
        {actions.applyCorrection ? (
          <AppButton variant="secondary" onClick={() => setCorrectionOpen(true)}>
            <Pencil className="size-4" aria-hidden="true" />
            {t("dataRequests.actions.applyCorrection")}
          </AppButton>
        ) : null}
        {actions.erase ? (
          <AppButton variant="destructive" onClick={() => setErasureOpen(true)}>
            <ShieldAlert className="size-4" aria-hidden="true" />
            {t("dataRequests.actions.runErasure")}
          </AppButton>
        ) : null}
        {actions.exportData ? (
          <AppButton variant="secondary" onClick={onExport} loading={exportData.isPending}>
            <Download className="size-4" aria-hidden="true" />
            {t("dataRequests.actions.downloadExport")}
          </AppButton>
        ) : null}
      </div>
      {error ? (
        <p role="alert" className="text-small text-danger" data-testid="request-error">
          {error}
        </p>
      ) : null}

      {applied ? (
        <CorrectionTable
          rows={Object.entries(applied.applied)
            .map(([field, value]) => ({ field, value }))
            .sort((a, b) => a.field.localeCompare(b.field))}
          title={t("dataRequests.correction.appliedTitle")}
          testId="correction-applied"
        />
      ) : null}
      {erasure ? <ErasureReport result={erasure} /> : null}
      {exported ? (
        <section className="flex flex-col gap-2" data-testid="export-preview">
          <h3 className="text-small font-semibold text-text-secondary">
            {t("dataRequests.export.previewTitle")}
          </h3>
          <pre className="max-h-64 overflow-auto rounded-input border border-border bg-background p-3 text-small text-text">
            {exported}
          </pre>
        </section>
      ) : null}

      {startOpen ? (
        <Dialog
          open
          onOpenChange={(o) => !o && setStartOpen(false)}
          title={t("dataRequests.start.title")}
          description={t("dataRequests.start.help")}
          confirmLabel={t("dataRequests.start.confirm")}
          onConfirm={() => move("in_progress", undefined, t("dataRequests.start.done"))}
          loading={update.isPending}
          error={error}
        />
      ) : null}
      {noteAction ? (
        <NoteDialog
          action={noteAction}
          busy={update.isPending}
          error={error}
          onCancel={() => setNoteAction(null)}
          onConfirm={(note) =>
            move(
              noteAction === "complete" ? "completed" : "rejected",
              note,
              t(`dataRequests.${noteAction}.done`),
            )
          }
        />
      ) : null}
      {correctionOpen ? (
        <Dialog
          open
          onOpenChange={(o) => !o && setCorrectionOpen(false)}
          title={t("dataRequests.correction.title")}
          description={t("dataRequests.correction.help")}
          confirmLabel={t("dataRequests.correction.confirm")}
          loading={applyCorrection.isPending}
          error={error}
          onConfirm={() => {
            setError(undefined);
            applyCorrection.mutate(request.id, {
              onSuccess: (result) => {
                setApplied(result);
                setCorrectionOpen(false);
                toast.success(
                  t("dataRequests.correction.done", {
                    n: Object.keys(result.applied).length,
                  }),
                );
              },
              onError: fail,
            });
          }}
        >
          <div className="flex flex-col gap-2" data-testid="correction-diff">
            <CorrectionTable rows={changes} title={t("dataRequests.correction.requested")} />
            <p className="text-small text-text-muted">{t("dataRequests.stepUpNote")}</p>
          </div>
        </Dialog>
      ) : null}
      {erasureOpen ? (
        <Dialog
          open
          onOpenChange={(o) => !o && setErasureOpen(false)}
          title={t("dataRequests.erasure.title")}
          description={t("dataRequests.erasure.help")}
          confirmLabel={t("dataRequests.erasure.confirm")}
          destructive
          loading={runErasure.isPending}
          error={error}
          onConfirm={() => {
            setError(undefined);
            runErasure.mutate(request.id, {
              onSuccess: (result) => {
                setErasure(result);
                setErasureOpen(false);
                toast.success(t("dataRequests.erasure.done"));
              },
              onError: fail,
            });
          }}
        >
          <p className="text-small text-text-muted" data-testid="erasure-step-up-note">
            {t("dataRequests.stepUpNote")}
          </p>
        </Dialog>
      ) : null}
    </aside>
  );
}

function NoteDialog({
  action,
  busy,
  error,
  onCancel,
  onConfirm,
}: {
  action: NoteAction;
  busy: boolean;
  error?: string;
  onCancel: () => void;
  onConfirm: (note: string) => void;
}) {
  const t = useT();
  const [note, setNote] = React.useState("");
  const [missing, setMissing] = React.useState(false);
  return (
    <Dialog
      open
      onOpenChange={(o) => !o && onCancel()}
      title={t(`dataRequests.${action}.title`)}
      description={t(`dataRequests.${action}.help`)}
      confirmLabel={t(`dataRequests.${action}.confirm`)}
      destructive={action === "reject"}
      loading={busy}
      error={error}
      onConfirm={() => {
        const value = note.trim();
        setMissing(!value);
        if (value) onConfirm(value);
      }}
    >
      <TextAreaField
        label={t("dataRequests.note.label")}
        value={note}
        rows={3}
        maxLength={2000}
        onChange={(e) => {
          setNote(e.target.value);
          setMissing(false);
        }}
        error={missing ? t("dataRequests.note.required") : undefined}
        data-testid="resolution-note"
      />
      <p className="text-small text-text-muted">{t("dataRequests.note.help")}</p>
    </Dialog>
  );
}

function CorrectionTable({
  rows,
  title,
  testId,
}: {
  rows: ReadonlyArray<{ field: string; value: string }>;
  title: string;
  testId?: string;
}) {
  const t = useT();
  return (
    <section className="flex flex-col gap-2" data-testid={testId}>
      <h3 className="text-small font-semibold text-text-secondary">{title}</h3>
      {rows.length ? (
        <table className="w-full text-small">
          <thead>
            <tr className="text-left text-text-muted">
              <th scope="col" className="py-1 pr-3 font-semibold">
                {t("dataRequests.correction.field")}
              </th>
              <th scope="col" className="py-1 font-semibold">
                {t("dataRequests.correction.value")}
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.field} className="border-t border-border" data-testid="correction-row">
                <td className="py-1 pr-3 font-mono text-text-secondary">{row.field}</td>
                <td className="py-1 text-text">{row.value}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <p className="text-small text-text-muted">{t("dataRequests.correction.none")}</p>
      )}
    </section>
  );
}

/** What the erasure removed and what a statute makes us keep (financial records: 8 years). */
function ErasureReport({ result }: { result: ErasureResult }) {
  const t = useT();
  return (
    <section className="flex flex-col gap-3" data-testid="erasure-report">
      <h3 className="text-small font-semibold text-text-secondary">
        {t("dataRequests.erasure.reportTitle")}
      </h3>
      <div className="flex flex-col gap-1">
        <h4 className="text-small font-semibold text-text">
          {t("dataRequests.erasure.erasedTitle")}
        </h4>
        <ul className="flex flex-wrap gap-1" data-testid="erased-classes">
          {result.erased.map((name) => (
            <li key={name}>
              <Badge variant="neutral">{name}</Badge>
            </li>
          ))}
        </ul>
      </div>
      <div className="flex flex-col gap-1">
        <h4 className="text-small font-semibold text-text">
          {t("dataRequests.erasure.retainedTitle")}
        </h4>
        <p className="text-small text-text-muted">{t("dataRequests.erasure.retainedHelp")}</p>
        <ul className="flex flex-col gap-2" data-testid="retained-classes">
          {result.retained.map((item) => (
            <li
              key={item.class}
              className="rounded-input border border-border bg-background p-2"
              data-testid="retained-class"
              data-class={item.class}
            >
              <p className="font-mono text-small text-text">{item.class}</p>
              <p className="text-small text-text-secondary">{item.reason}</p>
              <p className="text-small text-text-muted">
                {t("dataRequests.erasure.retainedUntil", { date: formatDateTimeIst(item.until) })}
              </p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
