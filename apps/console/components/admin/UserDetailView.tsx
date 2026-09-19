"use client";

/**
 * C101 user detail (WC-011): edit name / role / status / store / cluster, forced logout,
 * deactivate, and the device list with bind (rebind a field officer's phone) and report lost.
 * Every security action asks for a confirmation first and then goes through step-up (SEC-028).
 */
import * as React from "react";
import Link from "next/link";
import { ArrowLeft, LogOut, ShieldOff, Smartphone } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { AppTextField } from "@/components/ds/AppTextField";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Dialog } from "@/components/ds/Dialog";
import { Skeleton } from "@/components/ds/Skeleton";
import { toast } from "@/components/ds/Toasts";
import {
  STAFF_ROLES,
  USER_READ_ROLES,
  USER_WRITE_ROLES,
  type AdminUser,
  type Device,
  type UserUpdateBody,
} from "@/lib/admin";
import { can } from "@/lib/catalog";
import { formatDateIst, formatDateTimeIst } from "@/lib/format";
import {
  useBindDevice,
  useDeactivateUser,
  useDevices,
  useForceLogout,
  useReportLost,
  useUpdateUser,
  useUser,
} from "@/lib/hooks/admin";
import { useClusterMap } from "@/lib/hooks/clusters";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { AdminSubNav } from "./AdminSubNav";
import { DeviceStatusBadge, UserStatusBadge, clusterLabel, useStoreLabels } from "./badges";
import { Field, QueryError, RoleGate, SelectField, SessionGate, roleLabel } from "./common";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "./StepUp";

export function UserDetailView({ id }: { id: string }) {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C101">
      <AdminSubNav />
      <Link
        href="/admin/users"
        className="inline-flex items-center gap-1 self-start text-small font-semibold text-primary hover:underline"
      >
        <ArrowLeft className="size-4" aria-hidden="true" />
        {t("users.back")}
      </Link>
      <SessionGate>
        <RoleGate roles={USER_READ_ROLES}>
          <StepUpProvider>
            <UserContent id={id} />
          </StepUpProvider>
        </RoleGate>
      </SessionGate>
    </div>
  );
}

/** A confirmed action: confirmation dialog -> step-up (inside the mutation) -> toast. */
interface Pending {
  title: string;
  body: string;
  confirm: string;
  destructive?: boolean;
  run: () => Promise<unknown>;
  done: string;
}

function UserContent({ id }: { id: string }) {
  const q = useUser(id);
  if (q.isLoading)
    return (
      <div className="flex flex-col gap-3">
        <Skeleton announce className="h-10 w-1/2" />
        <Skeleton className="h-48 w-full" />
      </div>
    );
  if (q.error || !q.data) return <QueryError error={q.error} onRetry={() => void q.refetch()} />;
  return <UserDetail user={q.data} />;
}

function UserDetail({ user }: { user: AdminUser }) {
  const t = useT();
  const session = useSession();
  const canWrite = can(session.role, USER_WRITE_ROLES);
  const isSelf = session.user?.id === user.id;
  const stepUp = useStepUp();
  const forceLogout = useForceLogout(stepUp);
  const deactivate = useDeactivateUser(stepUp);
  const stores = useStoreLabels();
  const clusterMap = useClusterMap();
  const [pending, setPending] = React.useState<Pending | null>(null);
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | undefined>();

  const confirmPending = async () => {
    if (!pending) return;
    setBusy(true);
    setError(undefined);
    try {
      await pending.run();
      toast.success(pending.done);
      setPending(null);
    } catch (err) {
      setError(isStepUpCancelled(err) ? t("stepUp.cancelled") : problemMessage(err, t));
    } finally {
      setBusy(false);
    }
  };

  const ask = (p: Pending) => {
    setError(undefined);
    setPending(p);
  };

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-display">{user.name}</h1>
          <UserStatusBadge status={user.status} />
        </div>
        <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Field label={t("users.columns.role")}>{roleLabel(t, user.role)}</Field>
          <Field label={t("users.columns.phone")}>
            <span className="tnum">{user.phone}</span>
          </Field>
          <Field label={t("users.columns.assignment")}>
            {[
              user.store_id ? (stores.get(user.store_id) ?? user.store_id) : null,
              user.cluster_id ? clusterLabel(t, user.cluster_id, clusterMap) : null,
            ]
              .filter(Boolean)
              .join(" · ") || t("users.tenantWide")}
          </Field>
          <Field label={t("users.createdAt")}>
            <span className="tnum">{formatDateIst(user.created_at)}</span>
          </Field>
        </dl>
        {canWrite && !isSelf ? (
          <div className="flex flex-wrap gap-2" data-testid="security-actions">
            <AppButton
              variant="secondary"
              size="M"
              onClick={() =>
                ask({
                  title: t("users.forceLogout.title", { name: user.name }),
                  body: t("users.forceLogout.body"),
                  confirm: t("users.forceLogout.confirm"),
                  destructive: true,
                  run: () => forceLogout.mutateAsync(user.id),
                  done: t("users.forceLogout.done", { name: user.name }),
                })
              }
            >
              <LogOut className="size-4" aria-hidden="true" />
              {t("users.forceLogout.action")}
            </AppButton>
            {user.status === "active" ? (
              <AppButton
                variant="destructive"
                size="M"
                onClick={() =>
                  ask({
                    title: t("users.deactivate.title", { name: user.name }),
                    body: t("users.deactivate.body"),
                    confirm: t("users.deactivate.confirm"),
                    destructive: true,
                    run: () => deactivate.mutateAsync(user.id),
                    done: t("users.deactivate.done", { name: user.name }),
                  })
                }
              >
                <ShieldOff className="size-4" aria-hidden="true" />
                {t("users.deactivate.action")}
              </AppButton>
            ) : null}
          </div>
        ) : isSelf ? (
          <p className="text-small text-text-muted">{t("users.selfNote")}</p>
        ) : null}
      </header>

      {canWrite ? <EditUser user={user} stores={stores} onAsk={ask} isSelf={isSelf} /> : null}

      <Devices user={user} canWrite={canWrite} onAsk={ask} />

      {pending ? (
        <Dialog
          open
          onOpenChange={(o) => {
            if (!o) setPending(null);
          }}
          title={pending.title}
          description={pending.body}
          confirmLabel={pending.confirm}
          destructive={pending.destructive}
          onConfirm={() => void confirmPending()}
          loading={busy}
          error={error}
        >
          <p className="text-small text-text-secondary" data-testid="confirm-step-up-note">
            {t("users.stepUpNote")}
          </p>
        </Dialog>
      ) : null}
    </div>
  );
}

function EditUser({
  user,
  stores,
  onAsk,
  isSelf,
}: {
  user: AdminUser;
  stores: Map<string, string>;
  onAsk: (p: Pending) => void;
  isSelf: boolean;
}) {
  const t = useT();
  const { role: myRole } = useSession();
  const stepUp = useStepUp();
  const update = useUpdateUser(stepUp);
  const clusterMap = useClusterMap();
  const clusters = React.useMemo(() => [...clusterMap.values()], [clusterMap]);
  const [name, setName] = React.useState(user.name);
  const [role, setRole] = React.useState(user.role);
  const [status, setStatus] = React.useState(user.status);
  const [storeId, setStoreId] = React.useState(user.store_id ?? "");
  const [clusterId, setClusterId] = React.useState(user.cluster_id ?? "");
  const [error, setError] = React.useState<string | undefined>();

  React.useEffect(() => {
    setName(user.name);
    setRole(user.role);
    setStatus(user.status);
    setStoreId(user.store_id ?? "");
    setClusterId(user.cluster_id ?? "");
  }, [user]);

  const body: UserUpdateBody = {};
  if (name.trim() !== user.name) body.name = name.trim();
  if (role !== user.role) body.role = role;
  if (status !== user.status) body.status = status as "active" | "disabled";
  if ((storeId || null) !== user.store_id) body.store_id = storeId || null;
  if ((clusterId || null) !== user.cluster_id) body.cluster_id = clusterId || null;
  const dirty = Object.keys(body).length > 0;
  const lockOwner = user.role === "owner" && myRole !== "owner";
  const roles = STAFF_ROLES.filter(
    (r) => r !== "owner" || myRole === "owner" || user.role === "owner",
  );

  const save = () => {
    if (!name.trim()) return setError(t("validation.required"));
    setError(undefined);
    const run = () => update.mutateAsync({ id: user.id, body });
    if (body.role !== undefined || body.status !== undefined) {
      onAsk({
        title: t("users.edit.confirmTitle", { name: user.name }),
        body:
          body.status === "disabled"
            ? t("users.deactivate.body")
            : t("users.edit.confirmBody", { role: roleLabel(t, role) }),
        confirm: t("users.edit.confirm"),
        destructive: body.status === "disabled",
        run,
        done: t("users.edit.saved"),
      });
      return;
    }
    run()
      .then(() => toast.success(t("users.edit.saved")))
      .catch((err: unknown) => setError(problemMessage(err, t)));
  };

  return (
    <section
      className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4"
      aria-labelledby="edit-user"
      data-testid="edit-user"
    >
      <h2 id="edit-user" className="text-heading font-semibold">
        {t("users.edit.title")}
      </h2>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <AppTextField
          label={t("users.fields.name")}
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={200}
          disabled={lockOwner}
        />
        <SelectField
          label={t("users.fields.role")}
          value={role}
          onChange={(e) => setRole(e.target.value)}
          options={roles.map((r) => ({ value: r, label: roleLabel(t, r) }))}
          disabled={isSelf || lockOwner}
        />
        <SelectField
          label={t("users.fields.status")}
          value={status}
          onChange={(e) => setStatus(e.target.value)}
          options={[
            { value: "active", label: t("users.status.active") },
            { value: "disabled", label: t("users.status.disabled") },
          ]}
          disabled={isSelf || lockOwner}
        />
        <SelectField
          label={t("users.fields.store")}
          value={storeId}
          onChange={(e) => setStoreId(e.target.value)}
          emptyLabel={t("common.none")}
          options={[...stores.entries()].map(([id, label]) => ({ value: id, label }))}
          disabled={lockOwner}
        />
        <SelectField
          label={t("users.fields.cluster")}
          value={clusterId}
          onChange={(e) => setClusterId(e.target.value)}
          emptyLabel={t("common.none")}
          options={clusters.map((c) => ({ value: c.id, label: c.name }))}
          disabled={lockOwner}
        />
      </div>
      {lockOwner ? <p className="text-small text-text-muted">{t("users.ownerLocked")}</p> : null}
      {error ? (
        <p role="alert" className="text-small text-danger">
          {error}
        </p>
      ) : null}
      <div className="flex justify-end">
        <AppButton onClick={save} disabled={!dirty} loading={update.isPending}>
          {t("common.save")}
        </AppButton>
      </div>
    </section>
  );
}

function Devices({
  user,
  canWrite,
  onAsk,
}: {
  user: AdminUser;
  canWrite: boolean;
  onAsk: (p: Pending) => void;
}) {
  const t = useT();
  const stepUp = useStepUp();
  const devices = useDevices(user.id);
  const bind = useBindDevice(stepUp);
  const lost = useReportLost(stepUp);
  const officer = user.role === "field_officer";

  const columns: DataTableColumn<Device>[] = [
    {
      id: "device",
      header: t("devices.columns.device"),
      cell: (d) => (
        <span className="flex flex-col">
          <span className="flex items-center gap-1 font-semibold">
            <Smartphone className="size-4 text-text-muted" aria-hidden="true" />
            {d.model ?? t("devices.unknownModel")}
          </span>
          <code className="text-small text-text-muted">{d.device_id}</code>
        </span>
      ),
    },
    {
      id: "platform",
      header: t("devices.columns.platform"),
      cell: (d) => [d.platform, d.app_version].filter(Boolean).join(" · ") || t("common.none"),
    },
    {
      id: "status",
      header: t("devices.columns.status"),
      cell: (d) => <DeviceStatusBadge status={d.status} />,
    },
    {
      id: "seen",
      header: t("devices.columns.lastSeen"),
      cell: (d) => <span className="tnum">{formatDateTimeIst(d.last_seen)}</span>,
    },
    {
      id: "bound",
      header: t("devices.columns.bound"),
      cell: (d) => (
        <span className="tnum">{d.bound_at ? formatDateIst(d.bound_at) : t("common.none")}</span>
      ),
    },
    ...(canWrite
      ? [
          {
            id: "actions",
            header: t("devices.columns.actions"),
            cell: (d: Device) => (
              <div className="flex flex-wrap gap-2">
                {d.status === "pending" || d.status === "revoked" ? (
                  <AppButton
                    size="M"
                    variant="secondary"
                    onClick={() =>
                      onAsk({
                        title: t("devices.bind.title", { device: d.model ?? d.device_id }),
                        body: officer ? t("devices.bind.bodyOfficer") : t("devices.bind.body"),
                        confirm: t("devices.bind.confirm"),
                        run: () => bind.mutateAsync({ userId: user.id, deviceId: d.device_id }),
                        done: t("devices.bind.done"),
                      })
                    }
                  >
                    {t("devices.bind.action")}
                  </AppButton>
                ) : null}
                {d.status === "active" || d.status === "pending" ? (
                  <AppButton
                    size="M"
                    variant="tertiary"
                    onClick={() =>
                      onAsk({
                        title: t("devices.lost.title", { device: d.model ?? d.device_id }),
                        body: t("devices.lost.body"),
                        confirm: t("devices.lost.confirm"),
                        destructive: true,
                        run: () => lost.mutateAsync({ userId: user.id, deviceId: d.device_id }),
                        done: t("devices.lost.done"),
                      })
                    }
                  >
                    {t("devices.lost.action")}
                  </AppButton>
                ) : null}
              </div>
            ),
          },
        ]
      : []),
  ];

  return (
    <section className="flex flex-col gap-3" aria-labelledby="devices-title" data-testid="devices">
      <div className="flex flex-col gap-1">
        <h2 id="devices-title" className="text-heading font-semibold">
          {t("devices.title")}
        </h2>
        <p className="text-small text-text-secondary">
          {officer ? t("devices.helpOfficer") : t("devices.help")}
        </p>
      </div>
      {devices.error ? (
        <QueryError error={devices.error} onRetry={() => void devices.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={devices.data?.items ?? []}
          rowKey={(d) => d.id}
          loading={devices.isLoading}
          caption={t("devices.title")}
          emptyTitle={t("devices.emptyTitle")}
          emptyHelp={t("devices.emptyHelp")}
        />
      )}
    </section>
  );
}
