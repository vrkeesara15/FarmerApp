"use client";

/**
 * C82 campaign results (WC-008 / AN-008): delivery counts, attributed orders and revenue, and
 * the own-brand and conversion lift against the holdout arm. The conversion window is spelled
 * out on the screen (last touch, `attribution_days` from each recipient's message), because the
 * numbers mean nothing without it. A bar comparison, never a pie (SPEC 13.4).
 */
import * as React from "react";
import { Info, Ban } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Dialog } from "@/components/ds/Dialog";
import { Skeleton } from "@/components/ds/Skeleton";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/analytics/Page";
import { QueryError, RoleGate, SessionGate } from "@/components/admin/common";
import { BarCompare, CHART_SERIES } from "@/components/analytics/charts";
import {
  CAMPAIGN_READ_ROLES,
  CAMPAIGN_WRITE_ROLES,
  RECIPIENT_STATUSES,
  type CampaignRecipient,
} from "@/lib/campaigns";
import { formatDateTimeIst, formatInrCompact, formatNumber, formatPercent } from "@/lib/format";
import {
  useCampaign,
  useCampaignRecipients,
  useCampaignRoi,
  useCancelCampaign,
} from "@/lib/hooks/growth";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { Choice, Note, Stat } from "./common";

export function CampaignResults({ id }: { id: string }) {
  return (
    <div className="flex flex-col gap-4" data-screen="C82">
      <SessionGate>
        <RoleGate roles={CAMPAIGN_READ_ROLES}>
          <Results id={id} />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

const pct = (v: number | null | undefined, na: string) =>
  v === null || v === undefined ? na : formatPercent(v, 1);

function Results({ id }: { id: string }) {
  const t = useT();
  const { role } = useSession();
  const campaign = useCampaign(id);
  const roi = useCampaignRoi(id, campaign.data ? campaign.data.status !== "draft" : false);
  const [status, setStatus] = React.useState<string>("");
  const recipients = useCampaignRecipients(id, status || undefined);
  const cancel = useCancelCampaign();
  const [confirmCancel, setConfirmCancel] = React.useState(false);
  const [error, setError] = React.useState<string | undefined>();
  const na = t("common.none");

  if (campaign.isLoading) return <Skeleton announce className="h-96 w-full" />;
  if (campaign.error)
    return <QueryError error={campaign.error} onRetry={() => void campaign.refetch()} />;
  const c = campaign.data!;
  const canWrite = !!role && CAMPAIGN_WRITE_ROLES.includes(role);
  const r = roi.data;

  const columns: ReadonlyArray<DataTableColumn<CampaignRecipient>> = [
    { id: "farmer", header: t("campaigns.results.column.farmer"), accessor: (x) => x.farmer_name },
    { id: "phone", header: t("campaigns.results.column.phone"), accessor: (x) => x.phone_masked },
    {
      id: "arm",
      header: t("campaigns.results.column.arm"),
      cell: (x) => (x.arm === "holdout" ? t("campaigns.arms.holdout") : t("campaigns.arms.target")),
    },
    {
      id: "language",
      header: t("campaigns.results.column.language"),
      accessor: (x) => x.language.toUpperCase(),
    },
    {
      id: "status",
      header: t("campaigns.results.column.status"),
      cell: (x) => (
        <Badge
          variant={
            x.status === "delivered"
              ? "success"
              : x.status === "failed"
                ? "danger"
                : x.status === "skipped"
                  ? "warning"
                  : "neutral"
          }
        >
          {t(`campaigns.results.recipientStatus.${x.status}`)}
        </Badge>
      ),
    },
    {
      id: "sentAt",
      header: t("campaigns.results.column.sentAt"),
      cell: (x) => (x.sent_at ? formatDateTimeIst(x.sent_at) : na),
    },
    {
      id: "reason",
      header: t("campaigns.results.column.reason"),
      cell: (x) =>
        x.skip_reason
          ? t(
              `campaigns.results.skipReason.${x.skip_reason}` as `campaigns.results.skipReason.no_app`,
            )
          : (x.error ?? na),
    },
  ];

  return (
    <>
      <PageHeader
        title={c.name}
        subtitle={
          <span className="flex flex-wrap items-center gap-2">
            <Badge>{t(`campaigns.channel.${c.channel}`)}</Badge>
            <Badge
              variant={c.status === "sent" ? "success" : "neutral"}
              data-testid="result-status"
            >
              {t(`campaigns.status.${c.status}`)}
            </Badge>
            {c.send_at ? (
              <span className="text-small text-text-muted">
                {t("campaigns.scheduledFor", { when: formatDateTimeIst(c.send_at) })}
              </span>
            ) : null}
          </span>
        }
        back={{ href: "/campaigns", label: t("campaigns.builder.back") }}
        actions={
          canWrite && (c.status === "draft" || c.status === "scheduled") ? (
            <AppButton variant="destructive" onClick={() => setConfirmCancel(true)}>
              <Ban className="size-4" aria-hidden="true" />
              {t("campaigns.cancel")}
            </AppButton>
          ) : null
        }
      />

      {c.status === "draft" ? (
        <Note testId="results-pending">{t("campaigns.results.pending")}</Note>
      ) : roi.isLoading ? (
        <Skeleton announce className="h-40 w-full" />
      ) : roi.error ? (
        <QueryError error={roi.error} onRetry={() => void roi.refetch()} />
      ) : r ? (
        <>
          <div
            className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-5"
            data-testid="roi-stats"
          >
            <Stat
              label={t("campaigns.results.sent")}
              value={formatNumber(r.sent)}
              testId="roi-sent"
            />
            <Stat
              label={t("campaigns.results.delivered")}
              value={formatNumber(r.delivered)}
              testId="roi-delivered"
            />
            <Stat
              label={t("campaigns.results.failed")}
              value={formatNumber(r.failed)}
              tone={r.failed > 0 ? "danger" : undefined}
              testId="roi-failed"
            />
            {r.opened !== null ? (
              <Stat label={t("campaigns.results.opened")} value={formatNumber(r.opened)} />
            ) : (
              <Stat label={t("campaigns.results.skipped")} value={formatNumber(r.skipped)} />
            )}
            <Stat
              label={t("campaigns.results.orders")}
              value={formatNumber(r.orders)}
              help={pct(r.conversion_rate, na)}
              testId="roi-orders"
            />
            <Stat
              label={t("campaigns.results.revenue")}
              value={formatInrCompact(r.revenue_paise)}
              testId="roi-revenue"
            />
            <Stat
              label={t("campaigns.results.ownBrandShare")}
              value={pct(r.own_brand_share, na)}
              testId="roi-own-brand"
            />
            <Stat
              label={t("campaigns.results.ownBrandLift")}
              value={r.own_brand_lift === null ? na : formatPercent(r.own_brand_lift, 1)}
              tone={
                r.own_brand_lift === null ? undefined : r.own_brand_lift >= 0 ? "success" : "danger"
              }
              testId="roi-own-brand-lift"
            />
            <Stat
              label={t("campaigns.results.conversionLift")}
              value={r.conversion_lift === null ? na : formatPercent(r.conversion_lift, 1)}
              tone={
                r.conversion_lift === null
                  ? undefined
                  : r.conversion_lift >= 0
                    ? "success"
                    : "danger"
              }
              testId="roi-conversion-lift"
            />
          </div>

          <Note icon={<Info className="size-4" aria-hidden="true" />} testId="conversion-window">
            {t("campaigns.results.window", { days: r.attribution_days })}
          </Note>

          {r.holdout ? (
            <section
              className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4"
              data-testid="holdout-compare"
            >
              <h2 className="text-heading font-semibold">{t("campaigns.results.holdout")}</h2>
              <BarCompare
                label={t("campaigns.results.holdout")}
                categoryKey="metric"
                data={[
                  {
                    metric: t("campaigns.results.conversion"),
                    target: (r.conversion_rate ?? 0) * 100,
                    holdout: (r.holdout.conversion_rate ?? 0) * 100,
                  },
                  {
                    metric: t("campaigns.results.ownBrandShare"),
                    target: (r.own_brand_share ?? 0) * 100,
                    holdout: (r.holdout.own_brand_share ?? 0) * 100,
                  },
                ]}
                series={[
                  { key: "target", label: t("campaigns.arms.target"), color: CHART_SERIES[0]! },
                  { key: "holdout", label: t("campaigns.arms.holdout"), color: CHART_SERIES[1]! },
                ]}
                valueFormat={(v) => `${v.toFixed(1)}%`}
              />
            </section>
          ) : (
            <Note tone="warning" testId="no-holdout">
              {t("campaigns.results.noHoldout")}
            </Note>
          )}
        </>
      ) : null}

      <section className="flex flex-col gap-3">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <h2 className="text-heading font-semibold">{t("campaigns.results.recipients")}</h2>
          <Choice
            id="recipient-status"
            label={t("campaigns.results.column.status")}
            value={status}
            includeAll
            options={RECIPIENT_STATUSES.map((s) => ({
              value: s,
              label: t(`campaigns.results.recipientStatus.${s}`),
            }))}
            onChange={(v) => setStatus(v)}
          />
        </div>
        <DataTable
          columns={columns}
          rows={recipients.data?.items ?? []}
          rowKey={(x) => x.farmer_id}
          loading={recipients.isLoading}
          error={recipients.error ? problemMessage(recipients.error, t) : undefined}
          onRetry={() => void recipients.refetch()}
          caption={t("campaigns.results.recipients")}
          emptyTitle={t("campaigns.results.pending")}
        />
      </section>

      {error ? (
        <p className="text-body text-danger" role="alert">
          {error}
        </p>
      ) : null}

      <Dialog
        open={confirmCancel}
        onOpenChange={setConfirmCancel}
        title={t("campaigns.cancelTitle")}
        description={t("campaigns.cancelHelp")}
        confirmLabel={t("campaigns.cancel")}
        destructive
        loading={cancel.isPending}
        onConfirm={() => {
          setError(undefined);
          cancel.mutate(id, {
            onSuccess: () => {
              toast.success(t("campaigns.toast.cancelled"));
              setConfirmCancel(false);
            },
            onError: (err) => setError(problemMessage(err, t)),
          });
        }}
      />
    </>
  );
}
