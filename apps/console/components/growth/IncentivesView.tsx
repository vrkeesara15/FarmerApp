"use client";

/**
 * C90 targets and incentives (WC-009). Three tabs, all bound to the chosen month in the URL:
 *
 * - Targets: the monthly target per officer and store, editable in place.
 * - Incentive rules: the version history and the rule editor, with a payout preview per officer
 *   that evaluates the **unsaved** document (`POST /v1/incentives/preview`), and publishing a
 *   new version.
 * - Payouts: the frozen payouts of a closed month, and closing a month behind step-up.
 *
 * VV-005: the screen states, from the active document, whether the rules count verified visits
 * only (the default) or a wider set (`verifiedVisitsNote()`).
 */
import * as React from "react";
import { BadgeCheck, Lock, ShieldCheck } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Dialog } from "@/components/ds/Dialog";
import { Skeleton } from "@/components/ds/Skeleton";
import { Tabs } from "@/components/ds/Tabs";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/analytics/Page";
import { QueryError, RoleGate, SessionGate } from "@/components/admin/common";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "@/components/admin/StepUp";
import {
  INCENTIVE_CLOSE_ROLES,
  INCENTIVE_READ_ROLES,
  INCENTIVE_WRITE_ROLES,
  isMonth,
  previousMonth,
  recentMonths,
  starterDefinition,
  validateDefinition,
  verifiedVisitsNote,
  type IncentiveOut,
  type RuleDefinition,
  type RuleSet,
  type TargetPatch,
  type TargetRow,
  type TargetSubject,
} from "@/lib/incentives";
import { formatInr, formatNumber, formatDateIst } from "@/lib/format";
import {
  useActivateRules,
  useCloseIncentives,
  useIncentiveRules,
  usePayouts,
  usePreviewDefinition,
  usePublishRules,
  useSaveTargets,
  useTargets,
} from "@/lib/hooks/growth";
import { useFilterOptions } from "@/lib/hooks/analytics";
import { useSearchParam } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { Choice, Note, NumberField, Stat, TextField } from "./common";
import { RuleEditor, RuleIssues } from "./RuleEditor";

const RUPEES = 100;

export function IncentivesView() {
  return (
    <div className="flex flex-col gap-4" data-screen="C90">
      <SessionGate>
        <RoleGate roles={INCENTIVE_READ_ROLES}>
          <StepUpProvider>
            <Incentives />
          </StepUpProvider>
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function Incentives() {
  const t = useT();
  const [monthParam, setMonth] = useSearchParam("month");
  const [tab, setTab] = useSearchParam("tab");
  const month = monthParam && isMonth(monthParam) ? monthParam : previousMonth();
  const months = React.useMemo(() => recentMonths(12), []);
  const rules = useIncentiveRules();
  const active = rules.data?.items.find((r) => r.status === "active") ?? null;
  const note = verifiedVisitsNote(active?.definition);

  return (
    <>
      <PageHeader
        title={t("incentives.title")}
        subtitle={t("incentives.subtitle")}
        actions={
          <Choice
            id="incentive-month"
            label={t("incentives.month")}
            value={month}
            options={months.map((m) => ({ value: m, label: m }))}
            onChange={(m) => setMonth(m || undefined)}
          />
        }
      />
      <Note
        icon={<BadgeCheck className="size-4" aria-hidden="true" />}
        tone={note.key === "widened" ? "warning" : "info"}
        testId="verified-visits-note"
      >
        {note.key === "verifiedOnly"
          ? t("incentives.verifiedVisits.verifiedOnly")
          : t("incentives.verifiedVisits.widened", { statuses: note.statuses.join(", ") })}
      </Note>

      <Tabs
        label={t("incentives.title")}
        value={(tab === "rules" || tab === "payouts" ? tab : "targets") as string}
        onValueChange={(v) => setTab(v === "targets" ? undefined : v)}
        items={[
          {
            value: "targets",
            label: t("incentives.tab.targets"),
            content: <TargetsTab month={month} />,
          },
          {
            value: "rules",
            label: t("incentives.tab.rules"),
            content: (
              <RulesTab
                month={month}
                rules={rules.data?.items ?? []}
                loading={rules.isLoading}
                error={rules.error}
                onRetry={() => void rules.refetch()}
              />
            ),
          },
          {
            value: "payouts",
            label: t("incentives.tab.payouts"),
            content: <PayoutsTab month={month} />,
          },
        ]}
      />
    </>
  );
}

// ---- targets -------------------------------------------------------------------------------

function TargetsTab({ month }: { month: string }) {
  const t = useT();
  const { role } = useSession();
  const [subject, setSubject] = React.useState<TargetSubject>("officer");
  const targets = useTargets(month, subject);
  const save = useSaveTargets();
  const [edits, setEdits] = React.useState<Record<string, Partial<TargetPatch>>>({});
  const [error, setError] = React.useState<string | undefined>();
  const canWrite = !!role && [...INCENTIVE_WRITE_ROLES, "cluster_head"].includes(role);

  React.useEffect(() => setEdits({}), [month, subject]);

  const valueOf = (row: TargetRow, key: keyof TargetPatch): number | undefined => {
    const edit = edits[row.subject_id]?.[key];
    if (edit !== undefined && edit !== null) return Number(edit);
    const base = row[key as keyof TargetRow];
    return typeof base === "number" ? base : undefined;
  };
  const setValue = (row: TargetRow, key: keyof TargetPatch, v: number | undefined) =>
    setEdits((e) => ({ ...e, [row.subject_id]: { ...e[row.subject_id], [key]: v ?? null } }));

  const moneyColumn = (
    id: string,
    header: string,
    key: "sales_paise" | "collections_paise",
  ): DataTableColumn<TargetRow> => ({
    id,
    header,
    numeric: true,
    cell: (row) =>
      canWrite ? (
        <NumberField
          id={`${id}-${row.subject_id}`}
          label={header}
          className="[&>label]:sr-only"
          value={(valueOf(row, key) ?? 0) / RUPEES}
          min={0}
          onChange={(v) => setValue(row, key, v === undefined ? undefined : v * RUPEES)}
        />
      ) : (
        formatInr(valueOf(row, key) ?? 0, { paise: "never" })
      ),
  });

  const countColumn = (
    id: string,
    header: string,
    key: "visits_verified" | "new_farmers" | "own_brand_share_bp",
  ): DataTableColumn<TargetRow> => ({
    id,
    header,
    numeric: true,
    cell: (row) =>
      canWrite ? (
        <NumberField
          id={`${id}-${row.subject_id}`}
          label={header}
          className="[&>label]:sr-only"
          value={valueOf(row, key)}
          min={0}
          onChange={(v) => setValue(row, key, v)}
        />
      ) : (
        formatNumber(valueOf(row, key) ?? 0)
      ),
  });

  const columns: ReadonlyArray<DataTableColumn<TargetRow>> = [
    {
      id: "subject",
      header: t("incentives.targets.column.subject"),
      accessor: (r) => r.subject_name,
      cell: (r) => <span className="font-semibold">{r.subject_name}</span>,
    },
    countColumn("visits", t("incentives.targets.column.visits"), "visits_verified"),
    countColumn("farmers", t("incentives.targets.column.farmers"), "new_farmers"),
    moneyColumn("sales", t("incentives.targets.column.sales"), "sales_paise"),
    moneyColumn("collections", t("incentives.targets.column.collections"), "collections_paise"),
    countColumn("ownBrand", t("incentives.targets.column.ownBrand"), "own_brand_share_bp"),
  ];

  const onSave = () => {
    setError(undefined);
    const items: TargetPatch[] = Object.entries(edits).map(([subject_id, patch]) => ({
      subject_type: subject,
      subject_id,
      ...patch,
    }));
    if (items.length === 0) return;
    save.mutate(
      { month, items },
      {
        onSuccess: () => {
          setEdits({});
          toast.success(t("incentives.targets.saved"));
        },
        onError: (err) => setError(problemMessage(err, t)),
      },
    );
  };

  return (
    <div className="flex flex-col gap-3 pt-3" data-testid="targets-tab">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <Choice
          id="target-subject"
          label={t("incentives.targets.subject")}
          value={subject}
          options={[
            { value: "officer" as TargetSubject, label: t("incentives.targets.subjectOfficer") },
            { value: "store" as TargetSubject, label: t("incentives.targets.subjectStore") },
          ]}
          onChange={(v) => setSubject((v || "officer") as TargetSubject)}
        />
        {canWrite ? (
          <AppButton
            onClick={onSave}
            loading={save.isPending}
            disabled={Object.keys(edits).length === 0}
            data-testid="save-targets"
          >
            {t("incentives.targets.save")}
          </AppButton>
        ) : null}
      </div>
      <p className="text-small text-text-muted">{t("incentives.targets.help")}</p>
      {error ? (
        <p className="text-body text-danger" role="alert">
          {error}
        </p>
      ) : null}
      {targets.error ? (
        <QueryError error={targets.error} onRetry={() => void targets.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={targets.data?.items ?? []}
          rowKey={(r) => r.subject_id}
          loading={targets.isLoading}
          caption={t("incentives.targets.title")}
          emptyTitle={t("incentives.targets.empty")}
        />
      )}
    </div>
  );
}

// ---- rules + preview -------------------------------------------------------------------------

function RulesTab({
  month,
  rules,
  loading,
  error,
  onRetry,
}: {
  month: string;
  rules: RuleSet[];
  loading: boolean;
  error: unknown;
  onRetry: () => void;
}) {
  const t = useT();
  const { role } = useSession();
  const stepUp = useStepUp();
  const opts = useFilterOptions();
  const canWrite = !!role && INCENTIVE_WRITE_ROLES.includes(role);
  const active = rules.find((r) => r.status === "active") ?? null;

  const [draft, setDraft] = React.useState<RuleDefinition | null>(null);
  const [name, setName] = React.useState("");
  const [officer, setOfficer] = React.useState("");
  const [saveError, setSaveError] = React.useState<string | undefined>();
  const publish = usePublishRules();
  const activate = useActivateRules();
  const preview = usePreviewDefinition();

  React.useEffect(() => {
    if (!officer && opts.officers.length > 0) setOfficer(opts.officers[0]!.officer_id);
  }, [officer, opts.officers]);

  const definition = draft ?? active?.definition ?? starterDefinition();
  const issues = validateDefinition(definition);

  const startEdit = () => {
    setDraft(structuredClone(active?.definition ?? starterDefinition()));
    setName(
      active ? `${active.name} v${active.version + 1}` : t("incentives.rules.namePlaceholder"),
    );
  };

  const onPreview = () => {
    if (!officer) return;
    preview.mutate({ officer_id: officer, month, definition });
  };

  const onPublish = () => {
    setSaveError(undefined);
    void stepUp
      .run((headers) => publish.mutateAsync({ name, definition, activate: true, headers }))
      .then(() => {
        setDraft(null);
        toast.success(t("incentives.rules.publish"));
      })
      .catch((err: unknown) => {
        if (isStepUpCancelled(err)) return;
        setSaveError(problemMessage(err, t));
      });
  };

  if (loading) return <Skeleton announce className="h-96 w-full" />;
  if (error) return <QueryError error={error} onRetry={onRetry} />;

  return (
    <div className="flex flex-col gap-4 pt-3" data-testid="rules-tab">
      <section className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-heading font-semibold">{t("incentives.rules.title")}</h2>
          {canWrite ? (
            <AppButton variant="secondary" onClick={startEdit} data-testid="edit-rules">
              {draft ? t("incentives.rules.newVersion") : t("incentives.rules.editVersion")}
            </AppButton>
          ) : null}
        </div>
        <ul className="flex flex-col gap-1 text-small">
          {rules.map((r) => (
            <li key={r.id} className="flex flex-wrap items-center gap-2" data-testid="rule-version">
              <Badge
                variant={
                  r.status === "active" ? "success" : r.status === "retired" ? "neutral" : "default"
                }
              >
                {t(`incentives.rules.status.${r.status}` as "incentives.rules.status.active")}
              </Badge>
              <span className="font-semibold">
                {t("incentives.rules.version", { n: r.version })}
              </span>
              <span className="text-text-secondary">{r.name}</span>
              {r.activated_at ? (
                <span className="text-text-muted">
                  {t("incentives.rules.activeSince", { when: formatDateIst(r.activated_at) })}
                </span>
              ) : null}
              {canWrite && r.status === "draft" ? (
                <AppButton
                  variant="tertiary"
                  onClick={() =>
                    void stepUp
                      .run((headers) => activate.mutateAsync({ id: r.id, headers }))
                      .catch((err: unknown) => {
                        if (!isStepUpCancelled(err)) setSaveError(problemMessage(err, t));
                      })
                  }
                >
                  {t("incentives.rules.activate")}
                </AppButton>
              ) : null}
            </li>
          ))}
        </ul>
      </section>

      <RuleEditor value={definition} onChange={setDraft} disabled={!canWrite || !draft} />
      <RuleIssues issues={issues} />

      {canWrite && draft ? (
        <section className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-4">
          <TextField
            id="rules-name"
            label={t("incentives.rules.name")}
            value={name}
            onChange={setName}
            placeholder={t("incentives.rules.namePlaceholder")}
          />
          <AppButton
            onClick={onPublish}
            loading={publish.isPending}
            disabled={issues.length > 0 || name.trim().length < 3}
            data-testid="publish-rules"
          >
            <ShieldCheck className="size-4" aria-hidden="true" />
            {t("incentives.rules.publish")}
          </AppButton>
          <p className="text-small text-text-muted">{t("incentives.rules.publishHelp")}</p>
        </section>
      ) : null}
      {saveError ? (
        <p className="text-body text-danger" role="alert" data-testid="rules-error">
          {saveError}
        </p>
      ) : null}

      <section
        className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4"
        data-testid="payout-preview"
      >
        <h2 className="text-heading font-semibold">{t("incentives.preview.title")}</h2>
        <div className="flex flex-wrap items-end gap-3">
          <Choice
            id="preview-officer"
            label={t("incentives.preview.officer")}
            value={officer}
            options={opts.officers.map((o) => ({ value: o.officer_id, label: o.name }))}
            onChange={(v) => setOfficer(v)}
          />
          <AppButton
            onClick={onPreview}
            loading={preview.isPending}
            disabled={!officer || issues.length > 0}
            data-testid="run-preview"
          >
            {t("incentives.preview.run")}
          </AppButton>
          {draft ? (
            <span className="text-small text-text-muted">{t("incentives.preview.draftNote")}</span>
          ) : null}
        </div>
        <p className="text-small text-text-muted">{t("incentives.preview.help")}</p>
        {preview.error ? (
          <p className="text-body text-danger" role="alert">
            {problemMessage(preview.error, t)}
          </p>
        ) : preview.data ? (
          <PreviewResult result={preview.data} />
        ) : (
          <p className="text-body text-text-secondary">{t("incentives.preview.empty")}</p>
        )}
      </section>
    </div>
  );
}

/** The payout breakdown of a preview (or a frozen payout). */
export function PreviewResult({ result }: { result: IncentiveOut }) {
  const t = useT();
  return (
    <div className="flex flex-col gap-3" data-testid="preview-result">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={result.eligible ? "success" : "warning"} data-testid="preview-eligible">
          {result.eligible ? t("incentives.preview.eligible") : t("incentives.preview.ineligible")}
        </Badge>
        {result.status === "closed" ? (
          <Badge variant="neutral">{t("incentives.preview.closed")}</Badge>
        ) : null}
        {result.reasons.map((r) => (
          <span key={r} className="text-small text-warning">
            {t(`incentives.preview.reason.${r}` as "incentives.preview.reason.min_verified_visits")}
          </span>
        ))}
      </div>
      <table className="w-full text-small">
        <caption className="sr-only">{t("incentives.preview.title")}</caption>
        <thead>
          <tr className="text-left text-text-muted">
            <th scope="col">{t("incentives.preview.column.component")}</th>
            <th scope="col">{t("incentives.preview.column.metric")}</th>
            <th scope="col" className="text-right">
              {t("incentives.preview.column.value")}
            </th>
            <th scope="col" className="text-right">
              {t("incentives.preview.column.amount")}
            </th>
          </tr>
        </thead>
        <tbody>
          {result.lines.map((l) => (
            <tr key={l.component} data-testid="preview-line">
              <td>{l.component}</td>
              <td>{l.metric}</td>
              <td className="tnum text-right">{formatNumber(l.value)}</td>
              <td className="tnum text-right font-semibold">
                {formatInr(l.amount_paise)}
                {l.capped ? (
                  <span className="ml-1 text-text-muted">{t("incentives.preview.capped")}</span>
                ) : null}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="grid gap-3 sm:grid-cols-3">
        <Stat label={t("incentives.preview.gross")} value={formatInr(result.gross_paise)} />
        <Stat
          label={t("incentives.preview.clawback")}
          value={formatInr(result.clawback_paise)}
          tone={result.clawback_paise > 0 ? "danger" : undefined}
        />
        <Stat
          label={t("incentives.preview.total")}
          value={formatInr(result.amount_paise)}
          testId="preview-total"
        />
      </div>
    </div>
  );
}

// ---- payouts ---------------------------------------------------------------------------------

function PayoutsTab({ month }: { month: string }) {
  const t = useT();
  const { role } = useSession();
  const stepUp = useStepUp();
  const payouts = usePayouts(month);
  const close = useCloseIncentives();
  const [confirm, setConfirm] = React.useState(false);
  const [error, setError] = React.useState<string | undefined>();
  const canClose = !!role && INCENTIVE_CLOSE_ROLES.includes(role);

  const columns: ReadonlyArray<DataTableColumn<IncentiveOut>> = [
    {
      id: "officer",
      header: t("incentives.payouts.column.officer"),
      accessor: (p) => p.officer_name ?? p.officer_id,
    },
    {
      id: "amount",
      header: t("incentives.payouts.column.amount"),
      numeric: true,
      accessor: (p) => p.amount_paise,
      cell: (p) => formatInr(p.amount_paise),
    },
    {
      id: "status",
      header: t("incentives.payouts.column.status"),
      cell: (p) => (
        <Badge variant={p.status === "closed" ? "success" : "neutral"}>
          {p.status === "closed"
            ? t("incentives.preview.closed")
            : t("incentives.preview.eligible")}
        </Badge>
      ),
    },
  ];

  const onClose = () => {
    setError(undefined);
    void stepUp
      .run((headers) => close.mutateAsync({ month, headers }))
      .then(() => {
        toast.success(t("incentives.payouts.closed"));
        setConfirm(false);
      })
      .catch((err: unknown) => {
        if (isStepUpCancelled(err)) return;
        setError(problemMessage(err, t));
      });
  };

  return (
    <div className="flex flex-col gap-3 pt-3" data-testid="payouts-tab">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <Stat
          label={t("incentives.payouts.total")}
          value={formatInr(payouts.data?.total_paise ?? 0)}
          testId="payout-total"
        />
        {canClose ? (
          <AppButton onClick={() => setConfirm(true)} data-testid="close-month">
            <Lock className="size-4" aria-hidden="true" />
            {t("incentives.payouts.close")}
          </AppButton>
        ) : null}
      </div>
      {error ? (
        <p className="text-body text-danger" role="alert">
          {error}
        </p>
      ) : null}
      {payouts.error ? (
        <QueryError error={payouts.error} onRetry={() => void payouts.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={payouts.data?.items ?? []}
          rowKey={(p) => p.officer_id}
          loading={payouts.isLoading}
          caption={t("incentives.payouts.title")}
          emptyTitle={t("incentives.payouts.empty")}
        />
      )}
      <Dialog
        open={confirm}
        onOpenChange={setConfirm}
        title={t("incentives.payouts.closeTitle", { month })}
        description={t("incentives.payouts.closeHelp")}
        confirmLabel={t("incentives.payouts.close")}
        loading={close.isPending}
        error={error}
        onConfirm={onClose}
      />
    </div>
  );
}
