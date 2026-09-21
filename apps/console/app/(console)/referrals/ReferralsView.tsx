"use client";

/**
 * FM-013 referrals per store. Two tables: the per-store roll-up (invited / attributed /
 * rewarded, and what has actually been credited), and the recent referrals with the action
 * that marks one rewarded.
 *
 * The list never shows a phone number — the API returns the last four digits only (AN-014 /
 * SEC-026) — and a store manager only ever receives their own store's rows.
 */
import * as React from "react";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { AppButton } from "@/components/ds/AppButton";
import { AnalyticsGate, PageHeader, Section } from "@/components/analytics/Page";
import { isBlockingProblem, ProblemState } from "@/components/analytics/ProblemState";
import { Badge } from "@/components/ui/badge";
import type { ReferralRow, ReferralStatus, StoreReferralsRow } from "@/lib/analytics";
import { formatInr } from "@/lib/format";
import { formatDay } from "@/lib/analytics-format";
import { useReferrals, useReferralSummary, useRewardReferral } from "@/lib/hooks/analytics";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";

const STATUS_VARIANT: Record<ReferralStatus, "success" | "warning" | "neutral" | "danger"> = {
  pending: "neutral",
  attributed: "warning",
  rewarded: "success",
  rejected: "danger",
};

export function ReferralsView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C95">
      <AnalyticsGate path="/referrals" title={t("referrals.title")}>
        <Referrals />
      </AnalyticsGate>
    </div>
  );
}

function Referrals() {
  const t = useT();
  const summary = useReferralSummary();
  const list = useReferrals();
  const reward = useRewardReferral();
  const [error, setError] = React.useState<string | null>(null);

  const storeColumns: DataTableColumn<StoreReferralsRow>[] = React.useMemo(
    () => [
      {
        id: "store",
        header: t("referrals.columns.store"),
        accessor: (r) => r.store_name ?? r.store_code ?? "—",
        cell: (r) => r.store_name ?? r.store_code ?? "—",
        sortable: true,
      },
      { id: "code", header: t("referrals.columns.code"), cell: (r) => r.store_code ?? "—" },
      {
        id: "pending",
        header: t("referrals.columns.pending"),
        numeric: true,
        accessor: (r) => r.pending,
        cell: (r) => r.pending,
        sortable: true,
      },
      {
        id: "attributed",
        header: t("referrals.columns.attributed"),
        numeric: true,
        accessor: (r) => r.attributed,
        cell: (r) => r.attributed,
        sortable: true,
      },
      {
        id: "rewarded",
        header: t("referrals.columns.rewarded"),
        numeric: true,
        accessor: (r) => r.rewarded,
        cell: (r) => r.rewarded,
        sortable: true,
      },
      {
        id: "storeReward",
        header: t("referrals.columns.storeReward"),
        numeric: true,
        accessor: (r) => r.store_reward_paise,
        cell: (r) => formatInr(r.store_reward_paise),
        sortable: true,
      },
      {
        id: "total",
        header: t("referrals.columns.total"),
        numeric: true,
        accessor: (r) => r.total,
        cell: (r) => r.total,
        sortable: true,
      },
    ],
    [t],
  );

  const onReward = React.useCallback(
    (id: string) => {
      setError(null);
      reward.mutate(id, { onError: (err) => setError(problemMessage(err, t)) });
    },
    [reward, t],
  );

  const referralColumns: DataTableColumn<ReferralRow>[] = React.useMemo(
    () => [
      { id: "code", header: t("referrals.columns.code"), cell: (r) => r.code },
      {
        id: "status",
        header: t("referrals.columns.status"),
        cell: (r) => (
          <Badge variant={STATUS_VARIANT[r.status]}>{t(`referrals.status.${r.status}`)}</Badge>
        ),
      },
      {
        id: "source",
        header: t("referrals.columns.source"),
        cell: (r) =>
          r.source === "farmer_app" || r.source === "officer" || r.source === "invite"
            ? t(`referrals.source.${r.source}`)
            : r.source,
      },
      {
        id: "invited",
        header: t("referrals.columns.invited"),
        cell: (r) => (r.invited_phone_last4 ? `••• ${r.invited_phone_last4}` : "—"),
      },
      {
        id: "created",
        header: t("referrals.columns.created"),
        accessor: (r) => r.created_at,
        cell: (r) => formatDay(r.created_at.slice(0, 10)),
        sortable: true,
      },
      {
        id: "action",
        header: t("referrals.columns.action"),
        cell: (r) =>
          r.status === "attributed" ? (
            <AppButton
              variant="secondary"
              size="M"
              loading={reward.isPending && reward.variables === r.id}
              onClick={() => onReward(r.id)}
            >
              {t("referrals.reward")}
            </AppButton>
          ) : r.status === "rewarded" ? (
            <span className="text-small text-text-muted">{t("referrals.rewarded")}</span>
          ) : (
            <span className="text-small text-text-muted">—</span>
          ),
      },
    ],
    [onReward, reward.isPending, reward.variables, t],
  );

  const header = (
    <PageHeader title={t("referrals.title")} subtitle={t("referrals.subtitle")} />
  );

  const blocking = summary.error && isBlockingProblem(summary.error);
  if (blocking)
    return (
      <>
        {header}
        <ProblemState error={summary.error} />
      </>
    );

  return (
    <>
      {header}
      {error ? (
        <p className="text-small text-danger" data-testid="referral-error">
          {error}
        </p>
      ) : null}
      <Section title={t("referrals.perStore")} testId="referrals-per-store">
        <DataTable
          columns={storeColumns}
          rows={summary.data?.stores ?? []}
          rowKey={(r) => r.store_id ?? "none"}
          loading={summary.isLoading}
          error={summary.error ? problemMessage(summary.error, t) : undefined}
          onRetry={() => void summary.refetch()}
          emptyTitle={t("referrals.emptyTitle")}
          emptyHelp={t("referrals.emptyHelp")}
          caption={t("referrals.perStore")}
        />
      </Section>
      <Section title={t("referrals.recent")} testId="referrals-list">
        <DataTable
          columns={referralColumns}
          rows={list.data?.items ?? []}
          rowKey={(r) => r.id}
          loading={list.isLoading}
          error={list.error ? problemMessage(list.error, t) : undefined}
          onRetry={() => void list.refetch()}
          emptyTitle={t("referrals.emptyTitle")}
          emptyHelp={t("referrals.emptyHelp")}
          caption={t("referrals.recent")}
        />
      </Section>
    </>
  );
}
