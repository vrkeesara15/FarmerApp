"use client";

/**
 * C103 Audit log viewer (WC-103, FA-006): filters kept in the URL (entity, entity id, actor,
 * action, role, IST date range), a DataTable with an expandable before / after diff per row,
 * cursor pagination ("Load more") and a CSV export behind step-up (SEC-028).
 */
import * as React from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { ChevronDown, ChevronRight, Download } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { AppTextField } from "@/components/ds/AppTextField";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import {
  AUDIT_ROLES,
  STAFF_ROLES,
  adminApi,
  auditDiff,
  type AuditFilters,
  type AuditLog,
} from "@/lib/admin";
import { downloadText } from "@/lib/catalog";
import { formatDateTimeIst } from "@/lib/format";
import { useAuditLogs, useUserNames } from "@/lib/hooks/admin";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { AdminSubNav } from "./AdminSubNav";
import { AuditDiff } from "./AuditDiff";
import { PageHeader, QueryError, RoleGate, SelectField, SessionGate, roleLabel } from "./common";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "./StepUp";

/** Tables that write audit rows most often (free text is accepted too). */
export const AUDIT_ENTITIES = [
  "user",
  "device",
  "tenant",
  "flag",
  "farmer",
  "farm",
  "visit",
  "order",
  "payment",
  "khata_entry",
  "product",
  "sku",
  "label_claim",
  "price_list",
  "audit_log",
] as const;

const ENTITY_ID = /^[0-9A-Fa-f-]{1,36}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

interface Draft {
  entity: string;
  q: string;
  actor_id: string;
  actor_role: string;
  action: string;
  from: string;
  to: string;
}

const EMPTY: Draft = {
  entity: "",
  q: "",
  actor_id: "",
  actor_role: "",
  action: "",
  from: "",
  to: "",
};

/** IST calendar dates -> API instants (start of `from`, end of `to`). */
export function toAuditFilters(d: Draft): AuditFilters {
  return {
    entity: d.entity || undefined,
    q: d.q || undefined,
    actor_id: d.actor_id || undefined,
    actor_role: d.actor_role || undefined,
    action: d.action || undefined,
    from: DATE.test(d.from) ? `${d.from}T00:00:00+05:30` : undefined,
    to: DATE.test(d.to) ? `${d.to}T23:59:59.999+05:30` : undefined,
  };
}

export function AuditView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C103">
      <PageHeader title={t("audit.title")} subtitle={t("audit.subtitle")} />
      <AdminSubNav />
      <SessionGate>
        <RoleGate roles={AUDIT_ROLES}>
          <StepUpProvider>
            <React.Suspense fallback={null}>
              <AuditContent />
            </React.Suspense>
          </StepUpProvider>
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function draftFrom(params: URLSearchParams): Draft {
  return {
    entity: params.get("entity") ?? "",
    q: params.get("q") ?? params.get("entity_id") ?? "",
    actor_id: params.get("actor_id") ?? "",
    actor_role: params.get("actor_role") ?? "",
    action: params.get("action") ?? "",
    from: params.get("from") ?? "",
    to: params.get("to") ?? "",
  };
}

function AuditContent() {
  const t = useT();
  const router = useRouter();
  const pathname = usePathname() ?? "/admin/audit";
  const params = useSearchParams();
  const paramsKey = params?.toString() ?? "";
  const applied = React.useMemo(() => draftFrom(new URLSearchParams(paramsKey)), [paramsKey]);
  const [draft, setDraft] = React.useState<Draft>(applied);
  const [draftError, setDraftError] = React.useState<Partial<Record<keyof Draft, string>>>({});
  const [expanded, setExpanded] = React.useState<Set<string>>(new Set());
  const [exporting, setExporting] = React.useState(false);
  const names = useUserNames();
  const stepUp = useStepUp();

  React.useEffect(() => setDraft(applied), [applied]);

  const filters = React.useMemo(() => toAuditFilters(applied), [applied]);
  const logs = useAuditLogs(filters);
  const rows = React.useMemo(() => (logs.data?.pages ?? []).flatMap((p) => p.items), [logs.data]);

  const apply = (e?: React.FormEvent) => {
    e?.preventDefault();
    const errs: Partial<Record<keyof Draft, string>> = {};
    if (draft.q && !ENTITY_ID.test(draft.q.trim())) errs.q = t("audit.errors.entityId");
    if (draft.from && draft.to && draft.from > draft.to) errs.to = t("validation.dateOrder");
    setDraftError(errs);
    if (Object.keys(errs).length) return;
    const next = new URLSearchParams();
    for (const [k, v] of Object.entries(draft)) if (v.trim()) next.set(k, v.trim());
    const qs = next.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname);
  };

  const clear = () => {
    setDraft(EMPTY);
    setDraftError({});
    router.replace(pathname);
  };

  const onExport = async () => {
    setExporting(true);
    try {
      const csv = await stepUp.run((h) => adminApi.exportAuditLogs(filters, h));
      downloadText("audit-log.csv", csv);
      toast.success(t("audit.exported"));
    } catch (err) {
      toast.error(isStepUpCancelled(err) ? t("stepUp.cancelled") : problemMessage(err, t));
    } finally {
      setExporting(false);
    }
  };

  const toggle = (id: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const actorName = (log: AuditLog) =>
    log.actor_id ? (names.get(log.actor_id)?.name ?? log.actor_id) : t("audit.system");

  const columns: DataTableColumn<AuditLog>[] = [
    {
      id: "expand",
      header: "",
      width: "2.5rem",
      cell: (log) => (
        <button
          type="button"
          onClick={() => toggle(log.id)}
          aria-expanded={expanded.has(log.id)}
          aria-label={
            expanded.has(log.id)
              ? t("audit.hideChanges", { action: log.action })
              : t("audit.showChanges", { action: log.action })
          }
          className="rounded-input p-1 text-text-muted hover:text-text"
        >
          {expanded.has(log.id) ? (
            <ChevronDown className="size-4" aria-hidden="true" />
          ) : (
            <ChevronRight className="size-4" aria-hidden="true" />
          )}
        </button>
      ),
    },
    {
      id: "time",
      header: t("audit.columns.time"),
      cell: (log) => (
        <span className="tnum whitespace-nowrap">{formatDateTimeIst(log.created_at)}</span>
      ),
    },
    {
      id: "action",
      header: t("audit.columns.action"),
      cell: (log) => <code className="text-small font-semibold">{log.action}</code>,
    },
    {
      id: "entity",
      header: t("audit.columns.entity"),
      cell: (log) => (
        <span className="flex flex-col">
          <span>{log.entity}</span>
          <code className="text-small text-text-muted">{log.entity_id}</code>
        </span>
      ),
    },
    {
      id: "actor",
      header: t("audit.columns.actor"),
      cell: (log) => (
        <span className="flex flex-col">
          <span>{actorName(log)}</span>
          <span className="text-small text-text-muted">{roleLabel(t, log.actor_role)}</span>
        </span>
      ),
    },
    {
      id: "changes",
      header: t("audit.columns.changes"),
      cell: (log) => {
        const changed = auditDiff(log.before, log.after).filter((r) => r.changed);
        return changed.length ? (
          <span className="flex flex-wrap gap-1">
            {changed.slice(0, 4).map((r) => (
              <Badge key={r.field} variant="neutral">
                {r.field}
              </Badge>
            ))}
            {changed.length > 4 ? (
              <span className="text-small text-text-muted">
                {t("audit.more", { n: changed.length - 4 })}
              </span>
            ) : null}
          </span>
        ) : (
          <span className="text-small text-text-muted">{t("audit.diff.none")}</span>
        );
      },
    },
  ];

  const renderExpanded = (log: AuditLog) => (
    <div className="flex flex-col gap-3">
      <AuditDiff log={log} />
      <dl className="grid gap-x-6 gap-y-1 text-small text-text-secondary sm:grid-cols-2">
        {(
          [
            ["audit.meta.ip", log.ip],
            ["audit.meta.device", log.device_id],
            ["audit.meta.userAgent", log.user_agent],
            ["audit.meta.trace", log.trace_id],
          ] as const
        ).map(([key, value]) => (
          <div key={key} className="flex gap-1">
            <dt className="text-text-muted">{t(key)}:</dt>
            <dd className="break-all">{value ?? t("common.none")}</dd>
          </div>
        ))}
      </dl>
    </div>
  );

  const set = (k: keyof Draft, v: string) => setDraft((d) => ({ ...d, [k]: v }));
  const actors = [...names.values()].sort((a, b) => a.name.localeCompare(b.name));

  return (
    <div className="flex flex-col gap-4">
      <form
        onSubmit={apply}
        className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3"
        aria-label={t("audit.filters")}
        data-testid="audit-filters"
      >
        <div className="flex min-w-40 flex-col gap-1">
          <AppTextField
            label={t("audit.fields.entity")}
            value={draft.entity}
            onChange={(e) => set("entity", e.target.value)}
            list="audit-entities"
            maxLength={64}
          />
          <datalist id="audit-entities">
            {AUDIT_ENTITIES.map((e) => (
              <option key={e} value={e} />
            ))}
          </datalist>
        </div>
        <AppTextField
          label={t("audit.fields.entityId")}
          value={draft.q}
          onChange={(e) => set("q", e.target.value)}
          maxLength={36}
          error={draftError.q}
          className="min-w-56"
        />
        <SelectField
          label={t("audit.fields.actor")}
          value={draft.actor_id}
          onChange={(e) => set("actor_id", e.target.value)}
          emptyLabel={t("common.all")}
          options={actors.map((u) => ({ value: u.id, label: u.name }))}
          className="min-w-44"
        />
        <SelectField
          label={t("audit.fields.role")}
          value={draft.actor_role}
          onChange={(e) => set("actor_role", e.target.value)}
          emptyLabel={t("common.all")}
          options={[...STAFF_ROLES, "system"].map((r) => ({
            value: r,
            label: r === "system" ? t("audit.system") : roleLabel(t, r),
          }))}
          className="min-w-40"
        />
        <AppTextField
          label={t("audit.fields.action")}
          value={draft.action}
          onChange={(e) => set("action", e.target.value)}
          helper={t("audit.fields.actionHelp")}
          maxLength={64}
          className="min-w-56"
        />
        <AppTextField
          label={t("audit.fields.from")}
          type="date"
          value={draft.from}
          onChange={(e) => set("from", e.target.value)}
        />
        <AppTextField
          label={t("audit.fields.to")}
          type="date"
          value={draft.to}
          onChange={(e) => set("to", e.target.value)}
          error={draftError.to}
        />
        <div className="flex gap-2">
          <AppButton type="submit" size="M">
            {t("common.apply")}
          </AppButton>
          <AppButton type="button" size="M" variant="tertiary" onClick={clear}>
            {t("common.clear")}
          </AppButton>
        </div>
        <AppButton
          type="button"
          size="M"
          variant="secondary"
          className="ml-auto"
          onClick={() => void onExport()}
          loading={exporting}
        >
          <Download className="size-4" aria-hidden="true" />
          {t("audit.export")}
        </AppButton>
      </form>
      <p className="text-small text-text-muted">{t("audit.istNote")}</p>

      {logs.error ? (
        <QueryError error={logs.error} onRetry={() => void logs.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(log) => log.id}
          loading={logs.isLoading}
          caption={t("audit.title")}
          emptyTitle={t("audit.emptyTitle")}
          expandedKeys={expanded}
          renderExpanded={renderExpanded}
        />
      )}
      {logs.hasNextPage ? (
        <AppButton
          variant="secondary"
          className="self-center"
          onClick={() => void logs.fetchNextPage()}
          loading={logs.isFetchingNextPage}
        >
          {t("audit.loadMore")}
        </AppButton>
      ) : null}
    </div>
  );
}
