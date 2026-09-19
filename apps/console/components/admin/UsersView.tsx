"use client";

/**
 * C101 Users and roles (WC-011): every staff account with role, store / cluster, status and
 * device status; create a user (step-up). Row -> /admin/users/[id] for edits, devices and
 * forced logout.
 */
import * as React from "react";
import Link from "next/link";
import { Plus } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { AppTextField } from "@/components/ds/AppTextField";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Dialog } from "@/components/ds/Dialog";
import { toast } from "@/components/ds/Toasts";
import { ApiError } from "@/lib/api";
import {
  LANGUAGES,
  STAFF_ROLES,
  USER_READ_ROLES,
  USER_WRITE_ROLES,
  type AdminUser,
  type Language,
} from "@/lib/admin";
import { can } from "@/lib/catalog";
import { normaliseIndianMobile } from "@/lib/format";
import { useCreateUser, useUsers } from "@/lib/hooks/admin";
import { useClusterMap } from "@/lib/hooks/clusters";
import type { Cluster } from "@/lib/clusters";
import { useT } from "@/lib/i18n-client";
import { LOCALE_OPTIONS } from "@/lib/i18n";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { AdminSubNav } from "./AdminSubNav";
import { DeviceStatusBadge, UserStatusBadge, clusterLabel, useStoreLabels } from "./badges";
import { PageHeader, QueryError, RoleGate, SelectField, SessionGate, roleLabel } from "./common";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "./StepUp";

export function UsersView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C101">
      <PageHeader title={t("users.title")} subtitle={t("users.subtitle")} />
      <AdminSubNav />
      <SessionGate>
        <RoleGate roles={USER_READ_ROLES}>
          <StepUpProvider>
            <UsersContent />
          </StepUpProvider>
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function UsersContent() {
  const t = useT();
  const { role } = useSession();
  const canWrite = can(role, USER_WRITE_ROLES);
  const users = useUsers();
  const stores = useStoreLabels();
  const [q, setQ] = React.useState("");
  const [roleFilter, setRoleFilter] = React.useState("");
  const [status, setStatus] = React.useState("");
  const [createOpen, setCreateOpen] = React.useState(false);

  const rows = React.useMemo(() => {
    const needle = q.trim().toLowerCase();
    return (users.data ?? []).filter(
      (u) =>
        (!needle || u.name.toLowerCase().includes(needle) || u.phone.includes(needle)) &&
        (!roleFilter || u.role === roleFilter) &&
        (!status || u.status === status),
    );
  }, [users.data, q, roleFilter, status]);
  const clusterMap = useClusterMap();
  const clusters = React.useMemo(() => [...clusterMap.values()], [clusterMap]);

  const columns: DataTableColumn<AdminUser>[] = [
    {
      id: "name",
      header: t("users.columns.name"),
      sortable: true,
      accessor: (u) => u.name,
      cell: (u) => (
        <Link href={`/admin/users/${u.id}`} className="font-semibold text-primary hover:underline">
          {u.name}
        </Link>
      ),
    },
    { id: "phone", header: t("users.columns.phone"), accessor: (u) => u.phone, className: "tnum" },
    {
      id: "role",
      header: t("users.columns.role"),
      sortable: true,
      accessor: (u) => roleLabel(t, u.role),
    },
    {
      id: "assignment",
      header: t("users.columns.assignment"),
      cell: (u) =>
        [
          u.store_id ? (stores.get(u.store_id) ?? u.store_id) : null,
          u.cluster_id ? clusterLabel(t, u.cluster_id, clusterMap) : null,
        ]
          .filter(Boolean)
          .join(" · ") || t("users.tenantWide"),
    },
    {
      id: "status",
      header: t("users.columns.status"),
      sortable: true,
      accessor: (u) => u.status,
      cell: (u) => <UserStatusBadge status={u.status} />,
    },
    {
      id: "device",
      header: t("users.columns.device"),
      // Device status comes with the list (one request for the table).
      accessor: (u) => u.device_status ?? "none",
      cell: (u) => <DeviceStatusBadge status={u.device_status ?? "none"} />,
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end gap-3" data-testid="user-filters">
        <AppTextField
          label={t("common.search")}
          placeholder={t("users.searchPlaceholder")}
          value={q}
          onChange={(e) => setQ(e.target.value)}
          className="min-w-64"
        />
        <SelectField
          label={t("users.columns.role")}
          value={roleFilter}
          onChange={(e) => setRoleFilter(e.target.value)}
          emptyLabel={t("common.all")}
          options={STAFF_ROLES.map((r) => ({ value: r, label: roleLabel(t, r) }))}
          className="min-w-44"
        />
        <SelectField
          label={t("users.columns.status")}
          value={status}
          onChange={(e) => setStatus(e.target.value)}
          emptyLabel={t("common.all")}
          options={[
            { value: "active", label: t("users.status.active") },
            { value: "disabled", label: t("users.status.disabled") },
          ]}
          className="min-w-36"
        />
        {canWrite ? (
          <AppButton className="ml-auto" onClick={() => setCreateOpen(true)}>
            <Plus className="size-4" aria-hidden="true" />
            {t("users.create")}
          </AppButton>
        ) : null}
      </div>
      {users.error ? (
        <QueryError error={users.error} onRetry={() => void users.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(u) => u.id}
          loading={users.isLoading}
          caption={t("users.title")}
          emptyTitle={t("users.emptyTitle")}
        />
      )}
      {createOpen ? (
        <CreateUserDialog
          onClose={() => setCreateOpen(false)}
          clusters={clusters}
          stores={stores}
        />
      ) : null}
    </div>
  );
}

const STORE_ROLES = ["store_manager", "accountant"];
const CLUSTER_ROLES = ["cluster_head", "field_officer"];

function CreateUserDialog({
  onClose,
  clusters,
  stores,
}: {
  onClose: () => void;
  clusters: Cluster[];
  stores: Map<string, string>;
}) {
  const t = useT();
  const { role: myRole } = useSession();
  const stepUp = useStepUp();
  const create = useCreateUser(stepUp);
  const [phone, setPhone] = React.useState("");
  const [name, setName] = React.useState("");
  const [role, setRole] = React.useState<string>("field_officer");
  const [storeId, setStoreId] = React.useState("");
  const [clusterId, setClusterId] = React.useState("");
  const [language, setLanguage] = React.useState<Language | "">("");
  const [errors, setErrors] = React.useState<Record<string, string>>({});
  const [formError, setFormError] = React.useState<string | undefined>();

  const roles = STAFF_ROLES.filter((r) => r !== "owner" || myRole === "owner");

  const submit = () => {
    const next: Record<string, string> = {};
    const ten = normaliseIndianMobile(phone);
    if (!ten) next.phone = t("login.phoneInvalid");
    if (!name.trim()) next.name = t("validation.required");
    if (STORE_ROLES.includes(role) && !storeId) next.store_id = t("users.storeRequired");
    if (CLUSTER_ROLES.includes(role) && !clusterId) next.cluster_id = t("users.clusterRequired");
    setErrors(next);
    setFormError(undefined);
    if (Object.keys(next).length || !ten) return;
    create.mutate(
      {
        phone: `+91${ten}`,
        name: name.trim(),
        role,
        store_id: storeId || null,
        cluster_id: clusterId || null,
        language: language || null,
      },
      {
        onSuccess: (u) => {
          toast.success(t("users.created", { name: u.name }));
          onClose();
        },
        onError: (err) => {
          if (isStepUpCancelled(err)) return setFormError(t("stepUp.cancelled"));
          if (err instanceof ApiError && err.problem.code === "phone_taken")
            return setErrors({ phone: problemMessage(err, t) });
          if (err instanceof ApiError && err.problem.code === "invalid_assignment") {
            const field = typeof err.problem.field === "string" ? err.problem.field : "store_id";
            return setErrors({ [field]: problemMessage(err, t) });
          }
          setFormError(problemMessage(err, t));
        },
      },
    );
  };

  return (
    <Dialog
      open
      onOpenChange={(o) => {
        if (!o) onClose();
      }}
      title={t("users.createTitle")}
      description={t("users.createHelp")}
      confirmLabel={t("users.createConfirm")}
      onConfirm={submit}
      loading={create.isPending}
      error={formError}
    >
      <div className="grid gap-3 sm:grid-cols-2" data-testid="create-user-form">
        <AppTextField
          label={t("users.fields.phone")}
          phone
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          error={errors.phone}
        />
        <AppTextField
          label={t("users.fields.name")}
          value={name}
          onChange={(e) => setName(e.target.value)}
          error={errors.name}
          maxLength={200}
        />
        <SelectField
          label={t("users.fields.role")}
          value={role}
          onChange={(e) => setRole(e.target.value)}
          options={roles.map((r) => ({ value: r, label: roleLabel(t, r) }))}
        />
        <SelectField
          label={t("users.fields.language")}
          value={language}
          onChange={(e) => setLanguage(e.target.value as Language | "")}
          emptyLabel={t("users.fields.languageDefault")}
          options={LANGUAGES.map((l) => ({
            value: l,
            label: LOCALE_OPTIONS.find((o) => o.locale === l)?.nativeName ?? l,
          }))}
        />
        <SelectField
          label={t("users.fields.store")}
          value={storeId}
          onChange={(e) => setStoreId(e.target.value)}
          emptyLabel={t("common.none")}
          options={[...stores.entries()].map(([id, label]) => ({ value: id, label }))}
          error={errors.store_id}
        />
        <SelectField
          label={t("users.fields.cluster")}
          value={clusterId}
          onChange={(e) => setClusterId(e.target.value)}
          emptyLabel={t("common.none")}
          options={clusters.map((c) => ({ value: c.id, label: c.name }))}
          error={errors.cluster_id}
        />
      </div>
    </Dialog>
  );
}
