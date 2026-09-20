"use client";

/**
 * C80 campaigns list (WC-008): every campaign newest first, filtered by status, with the
 * consented audience size and the send time. A row opens C82 (results) — a draft opens the
 * builder instead, since it has no results yet.
 */
import * as React from "react";
import { useRouter } from "next/navigation";
import { Megaphone, Plus } from "lucide-react";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/analytics/Page";
import { QueryError, RoleGate, SessionGate } from "@/components/admin/common";
import {
  CAMPAIGN_READ_ROLES,
  CAMPAIGN_STATUSES,
  CAMPAIGN_WRITE_ROLES,
  type Campaign,
  type CampaignStatus,
} from "@/lib/campaigns";
import { formatDateTimeIst, formatNumber } from "@/lib/format";
import { useCampaigns } from "@/lib/hooks/growth";
import { useSearchParam } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";
import { useSession } from "@/lib/session-context";
import { Choice, LinkButton } from "./common";

const STATUS_VARIANT: Record<string, "default" | "success" | "warning" | "danger" | "neutral"> = {
  draft: "neutral",
  scheduled: "warning",
  sending: "warning",
  sent: "success",
  cancelled: "neutral",
  failed: "danger",
};

export function CampaignsView() {
  return (
    <div className="flex flex-col gap-4" data-screen="C80">
      <SessionGate>
        <RoleGate roles={CAMPAIGN_READ_ROLES}>
          <List />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function List() {
  const t = useT();
  const router = useRouter();
  const { role } = useSession();
  const [status, setStatus] = useSearchParam("status");
  const list = useCampaigns((status ?? "") as CampaignStatus | "");
  const items = React.useMemo(() => (list.data?.pages ?? []).flatMap((p) => p.items), [list.data]);
  const canWrite = !!role && CAMPAIGN_WRITE_ROLES.includes(role);

  const columns: ReadonlyArray<DataTableColumn<Campaign>> = [
    {
      id: "name",
      header: t("campaigns.column.name"),
      accessor: (c) => c.name,
      cell: (c) => <span className="font-semibold">{c.name}</span>,
    },
    {
      id: "channel",
      header: t("campaigns.column.channel"),
      cell: (c) => t(`campaigns.channel.${c.channel}`),
    },
    {
      id: "status",
      header: t("campaigns.column.status"),
      cell: (c) => (
        <Badge variant={STATUS_VARIANT[c.status] ?? "default"} data-testid="campaign-status">
          {t(`campaigns.status.${c.status}`)}
        </Badge>
      ),
    },
    {
      id: "audience",
      header: t("campaigns.column.audience"),
      numeric: true,
      accessor: (c) => c.audience ?? -1,
      cell: (c) => (c.audience === null ? t("common.none") : formatNumber(c.audience)),
    },
    {
      id: "sendAt",
      header: t("campaigns.column.sendAt"),
      accessor: (c) => c.send_at ?? "",
      cell: (c) => (c.send_at ? formatDateTimeIst(c.send_at) : t("common.none")),
    },
    {
      id: "created",
      header: t("campaigns.column.created"),
      accessor: (c) => c.created_at,
      cell: (c) => formatDateTimeIst(c.created_at),
    },
  ];

  return (
    <>
      <PageHeader
        title={t("campaigns.title")}
        subtitle={t("campaigns.subtitle")}
        actions={
          canWrite ? (
            <LinkButton href="/campaigns/new" testId="new-campaign">
              <Plus className="size-4" aria-hidden="true" />
              {t("campaigns.new")}
            </LinkButton>
          ) : null
        }
      />
      <div className="flex flex-wrap items-end gap-3">
        <Choice
          id="campaign-status"
          label={t("campaigns.filterStatus")}
          value={(status ?? "") as CampaignStatus | ""}
          includeAll
          options={CAMPAIGN_STATUSES.map((s) => ({ value: s, label: t(`campaigns.status.${s}`) }))}
          onChange={(v) => setStatus(v || undefined)}
        />
      </div>
      {list.error ? (
        <QueryError error={list.error} onRetry={() => void list.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={items}
          rowKey={(c) => c.id}
          loading={list.isLoading}
          caption={t("campaigns.title")}
          emptyTitle={t("campaigns.emptyTitle")}
          emptyHelp={t("campaigns.emptyHelp")}
          emptyAction={
            canWrite ? (
              <LinkButton href="/campaigns/new">
                <Megaphone className="size-4" aria-hidden="true" />
                {t("campaigns.new")}
              </LinkButton>
            ) : undefined
          }
          onRowClick={(c) =>
            router.push(c.status === "draft" ? `/campaigns/new?id=${c.id}` : `/campaigns/${c.id}`)
          }
        />
      )}
    </>
  );
}
