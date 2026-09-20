"use client";

/**
 * C91 travel allowance approvals (FA-023). Claims by officer and month, each next to the km the
 * server computed from that day's duty tracks (VV-006, capped by `ta_daily_km_cap`) and the
 * receipt photo, with approve / reject and a note (cluster head, or an admin). The monthly
 * statement (`GET /v1/travel/statement`) is shown for the chosen officer and exports as CSV.
 */
import * as React from "react";
import { Check, Download, Info, X } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Dialog } from "@/components/ds/Dialog";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/components/ds/Toasts";
import { PageHeader } from "@/components/analytics/Page";
import { QueryError, RoleGate, SessionGate, TextAreaField } from "@/components/admin/common";
import {
  CLAIM_DECIDE_ROLES,
  CLAIM_READ_ROLES,
  CLAIM_STATUSES,
  claimMonth,
  dayFor,
  num,
  type ClaimStatus,
  type TravelClaim,
  type TravelDay,
} from "@/lib/travel";
import { isMonth, previousMonth, recentMonths } from "@/lib/incentives";
import { csvFilename, downloadCsv, paiseToRupees, type CsvColumn } from "@/lib/csv";
import { formatDateIst, formatDateTimeIst, formatInr } from "@/lib/format";
import { useDecideClaim, useTravelClaims, useTravelStatement } from "@/lib/hooks/growth";
import { useFilterOptions } from "@/lib/hooks/analytics";
import { useSearchParam } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { Choice, Note, Stat } from "./common";

export function TravelView() {
  return (
    <div className="flex flex-col gap-4" data-screen="C91">
      <SessionGate>
        <RoleGate roles={CLAIM_READ_ROLES}>
          <Travel />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

const STATUS_VARIANT: Record<string, "default" | "success" | "danger"> = {
  submitted: "default",
  approved: "success",
  rejected: "danger",
};

function Travel() {
  const t = useT();
  const { role } = useSession();
  const opts = useFilterOptions();
  const [monthParam, setMonth] = useSearchParam("month");
  const [officerParam, setOfficer] = useSearchParam("officer");
  const [statusParam, setStatus] = useSearchParam("status");
  const month = monthParam && isMonth(monthParam) ? monthParam : previousMonth();
  const months = React.useMemo(() => recentMonths(12), []);
  const status = (statusParam ?? "submitted") as ClaimStatus | "";

  const claims = useTravelClaims({
    status: status || undefined,
    officer_id: officerParam || undefined,
  });
  const statement = useTravelStatement(month, officerParam || undefined);
  const decide = useDecideClaim();
  const [pending, setPending] = React.useState<{
    claim: TravelClaim;
    decision: "approve" | "reject";
  } | null>(null);
  const [note, setNote] = React.useState("");
  const [error, setError] = React.useState<string | undefined>();
  const canDecide = !!role && CLAIM_DECIDE_ROLES.includes(role);
  const na = t("common.none");

  const rows = React.useMemo(
    () =>
      (claims.data?.pages ?? [])
        .flatMap((p) => p.items)
        .filter((c) => claimMonth(c.claim_date) === month),
    [claims.data, month],
  );

  const columns: ReadonlyArray<DataTableColumn<TravelClaim>> = [
    {
      id: "officer",
      header: t("travel.column.officer"),
      accessor: (c) => c.officer_name ?? c.officer_id,
      cell: (c) => (
        <span className="font-semibold">
          {c.officer_name ?? opts.officerName(c.officer_id) ?? c.officer_id}
        </span>
      ),
    },
    {
      id: "date",
      header: t("travel.column.date"),
      accessor: (c) => c.claim_date,
      cell: (c) => formatDateIst(c.claim_date),
    },
    {
      id: "type",
      header: t("travel.column.type"),
      cell: (c) => t(`travel.type.${c.type}` as "travel.type.fuel"),
    },
    {
      id: "claimed",
      header: t("travel.column.claimed"),
      numeric: true,
      accessor: (c) => c.amount_paise,
      cell: (c) => formatInr(c.amount_paise),
    },
    {
      id: "computedKm",
      header: t("travel.column.computedKm"),
      numeric: true,
      accessor: (c) => num(c.km_computed) ?? -1,
      cell: (c) => {
        const km = num(c.km_computed);
        return km === null ? (
          <span className="text-text-muted">{t("travel.noKm")}</span>
        ) : (
          <span className="tnum" data-testid="computed-km">
            {t("travel.km", { km: km.toFixed(1) })}
          </span>
        );
      },
    },
    {
      id: "allowance",
      header: t("travel.column.allowance"),
      numeric: true,
      cell: (c) => {
        const day = dayFor(statement.data, c.claim_date);
        return day ? formatInr(day.ta_paise) : na;
      },
    },
    {
      id: "status",
      header: t("travel.column.status"),
      cell: (c) => (
        <Badge variant={STATUS_VARIANT[c.status] ?? "default"} data-testid="claim-status">
          {t(`travel.status.${c.status}` as "travel.status.submitted")}
        </Badge>
      ),
    },
    {
      id: "actions",
      header: t("travel.column.status"),
      cell: (c) =>
        c.status === "submitted" && canDecide ? (
          <span className="flex flex-wrap gap-2">
            <AppButton
              onClick={() => {
                setNote("");
                setError(undefined);
                setPending({ claim: c, decision: "approve" });
              }}
              data-testid={`approve-${c.id}`}
            >
              <Check className="size-4" aria-hidden="true" />
              {t("travel.approve")}
            </AppButton>
            <AppButton
              variant="tertiary"
              onClick={() => {
                setNote("");
                setError(undefined);
                setPending({ claim: c, decision: "reject" });
              }}
              data-testid={`reject-${c.id}`}
            >
              <X className="size-4" aria-hidden="true" />
              {t("travel.reject")}
            </AppButton>
          </span>
        ) : c.decided_at ? (
          <span className="text-small text-text-muted">
            {t("travel.decidedBy", { when: formatDateTimeIst(c.decided_at) })}
          </span>
        ) : (
          na
        ),
    },
  ];

  const run = () => {
    if (!pending) return;
    if (pending.decision === "reject" && note.trim().length === 0) {
      setError(t("travel.noteRequired"));
      return;
    }
    setError(undefined);
    decide.mutate(
      { id: pending.claim.id, decision: pending.decision, note: note.trim() || null },
      {
        onSuccess: () => {
          toast.success(
            t(pending.decision === "approve" ? "travel.toast.approved" : "travel.toast.rejected"),
          );
          setPending(null);
        },
        onError: (err) => setError(problemMessage(err, t)),
      },
    );
  };

  const exportStatement = () => {
    const s = statement.data;
    if (!s) return;
    const columns: CsvColumn<TravelDay>[] = [
      { header: "date", value: (d) => d.date },
      { header: "sessions", value: (d) => d.sessions },
      { header: "km", value: (d) => num(d.km) ?? 0 },
      { header: "km_capped", value: (d) => num(d.km_capped) ?? 0 },
      { header: "allowance_rupees", value: (d) => paiseToRupees(d.ta_paise) },
    ];
    downloadCsv(csvFilename(`travel-${s.officer_id}-${s.month}`), columns, s.days);
    toast.success(t("travel.toast.exported"));
  };

  return (
    <>
      <PageHeader
        title={t("travel.title")}
        subtitle={t("travel.subtitle")}
        actions={
          <div className="flex flex-wrap items-end gap-3">
            <Choice
              id="travel-month"
              label={t("incentives.month")}
              value={month}
              options={months.map((m) => ({ value: m, label: m }))}
              onChange={(m) => setMonth(m || undefined)}
            />
            <Choice
              id="travel-officer"
              label={t("travel.filterOfficer")}
              value={officerParam ?? ""}
              includeAll
              options={opts.officers.map((o) => ({ value: o.officer_id, label: o.name }))}
              onChange={(v) => setOfficer(v || undefined)}
            />
            <Choice
              id="travel-status"
              label={t("travel.filterStatus")}
              value={status}
              includeAll
              options={CLAIM_STATUSES.map((s) => ({
                value: s,
                label: t(`travel.status.${s}`),
              }))}
              onChange={(v) => setStatus(v || undefined)}
            />
          </div>
        }
      />

      <Note icon={<Info className="size-4" aria-hidden="true" />} testId="km-help">
        {t("travel.kmHelp", { cap: statement.data?.cap_km ?? 150 })}
      </Note>

      {claims.error ? (
        <QueryError error={claims.error} onRetry={() => void claims.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(c) => c.id}
          loading={claims.isLoading}
          caption={t("travel.title")}
          emptyTitle={t("travel.emptyTitle")}
          emptyHelp={t("travel.emptyHelp")}
          expandedKeys={new Set(rows.map((c) => c.id))}
          renderExpanded={(c) => <ClaimDetail claim={c} />}
        />
      )}

      <section
        className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4"
        data-testid="statement"
      >
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-heading font-semibold">{t("travel.statement.title")}</h2>
          <AppButton
            variant="secondary"
            onClick={exportStatement}
            disabled={!statement.data}
            data-testid="export-statement"
          >
            <Download className="size-4" aria-hidden="true" />
            {t("travel.statement.export")}
          </AppButton>
        </div>
        <p className="text-small text-text-muted">{t("travel.statement.help")}</p>
        {!officerParam ? (
          <p className="text-body text-text-secondary">{t("travel.statement.pick")}</p>
        ) : statement.error ? (
          <QueryError error={statement.error} onRetry={() => void statement.refetch()} />
        ) : statement.data ? (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
            <Stat
              label={t("travel.statement.km")}
              value={(num(statement.data.km_total) ?? 0).toFixed(1)}
            />
            <Stat
              label={t("travel.statement.kmCapped")}
              value={(num(statement.data.km_capped_total) ?? 0).toFixed(1)}
            />
            <Stat
              label={t("travel.statement.allowance")}
              value={formatInr(statement.data.ta_total_paise)}
            />
            <Stat
              label={t("travel.statement.claims")}
              value={formatInr(statement.data.claims_approved_paise)}
            />
            <Stat
              label={t("travel.statement.payable")}
              value={formatInr(statement.data.payable_paise)}
              testId="statement-payable"
            />
          </div>
        ) : null}
      </section>

      <Dialog
        open={!!pending}
        onOpenChange={(o) => {
          if (!o) setPending(null);
        }}
        title={pending?.decision === "reject" ? t("travel.rejectTitle") : t("travel.approveTitle")}
        description={t("travel.decideHelp")}
        confirmLabel={pending?.decision === "reject" ? t("travel.reject") : t("travel.approve")}
        destructive={pending?.decision === "reject"}
        loading={decide.isPending}
        error={error}
        onConfirm={run}
      >
        <TextAreaField
          label={t("travel.note")}
          placeholder={t("travel.notePlaceholder")}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          rows={3}
        />
      </Dialog>
    </>
  );
}

/** The claim's receipt photo and note, under the row. */
function ClaimDetail({ claim }: { claim: TravelClaim }) {
  const t = useT();
  return (
    <div className="flex flex-wrap items-start gap-4" data-testid={`claim-detail-${claim.id}`}>
      <div className="flex flex-col gap-1">
        <span className="text-small font-semibold text-text-secondary">{t("travel.receipt")}</span>
        {claim.receipt_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={claim.receipt_url}
            alt={t("travel.receiptAlt", { date: claim.claim_date })}
            className="h-40 w-auto rounded-card border border-border object-contain"
          />
        ) : (
          <span className="text-small text-text-muted">{t("travel.noReceipt")}</span>
        )}
      </div>
      {claim.note ? <p className="max-w-md text-small text-text-secondary">{claim.note}</p> : null}
      {claim.decision_note ? (
        <p className="max-w-md text-small text-text-muted">{claim.decision_note}</p>
      ) : null}
    </div>
  );
}
