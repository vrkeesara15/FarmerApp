"use client";

import * as React from "react";
import { Badge } from "@/components/ui/badge";
import type { DeviceStatus } from "@/lib/admin";
import type { Cluster } from "@/lib/clusters";
import { useStores } from "@/lib/hooks/catalog";
import { useT } from "@/lib/i18n-client";

export function UserStatusBadge({ status }: { status: string }) {
  const t = useT();
  return status === "active" ? (
    <Badge variant="success" data-testid="user-status">
      {t("users.status.active")}
    </Badge>
  ) : (
    <Badge variant="neutral" data-testid="user-status">
      {t("users.status.disabled")}
    </Badge>
  );
}

const DEVICE_VARIANT: Record<DeviceStatus | "none", "success" | "warning" | "danger" | "neutral"> =
  {
    active: "success",
    pending: "warning",
    lost: "danger",
    revoked: "neutral",
    none: "neutral",
  };

export function DeviceStatusBadge({ status }: { status: DeviceStatus | "none" }) {
  const t = useT();
  return (
    <Badge variant={DEVICE_VARIANT[status]} data-testid="device-status" data-status={status}>
      {t(`devices.status.${status}`)}
    </Badge>
  );
}

/** Store id -> "CODE · Name" (from /v1/catalog/stores); unknown ids show the id. */
export function useStoreLabels(enabled = true): Map<string, string> {
  const stores = useStores(enabled);
  return React.useMemo(
    () => new Map((stores.data ?? []).map((s) => [s.id, `${s.code} · ${s.name}`])),
    [stores.data],
  );
}

/** A cluster's name (GET /v1/clusters); ids the caller cannot see get a short label. */
export function clusterLabel(
  t: ReturnType<typeof useT>,
  id: string,
  clusters?: ReadonlyMap<string, Cluster>,
): string {
  return clusters?.get(id)?.name ?? t("users.clusterShort", { id: id.slice(-4) });
}
