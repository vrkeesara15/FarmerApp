"use client";

import * as React from "react";
import { CheckCircle2, History, Pencil, Plus, Archive } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { EmptyState } from "@/components/ds/EmptyState";
import { ErrorState } from "@/components/ds/ErrorState";
import { OwnBrandBadge } from "@/components/ds/OwnBrandBadge";
import { SkeletonText } from "@/components/ds/Skeleton";
import {
  CLAIM_APPROVE_ROLES,
  CLAIM_EDIT_ROLES,
  CLAIM_RETIRE_ROLES,
  CLAIM_STATUSES,
  can,
  type ClaimStatus,
  type LabelClaim,
} from "@/lib/catalog";
import { formatInr } from "@/lib/format";
import {
  useCrops,
  useLabelClaims,
  usePests,
  useProducts,
  useRecommendable,
} from "@/lib/hooks/catalog";
import { useLocale, useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import {
  ClaimStatusChip,
  PageHeader,
  ProductsSubNav,
  SelectField,
  SessionGate,
} from "../_components/fields";
import {
  ApproveDialog,
  ClaimEditorDialog,
  HistoryDrawer,
  RetireDialog,
  type Lookups,
  type SkuOption,
} from "./ClaimDialogs";

/** C51 Label claims editor (WC-005; SKU × crop × pest × dose × PHI). */
export function LabelClaimsView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C51">
      <PageHeader title={t("claims.title")} subtitle={t("claims.subtitle")} />
      <ProductsSubNav />
      <SessionGate>
        <LabelClaimsContent />
      </SessionGate>
    </div>
  );
}

function useLookups(): Lookups & { loading: boolean; error: unknown } {
  const locale = useLocale();
  const products = useProducts({ include_inactive: true });
  const crops = useCrops();
  const pests = usePests();
  return React.useMemo(() => {
    const skus: SkuOption[] = (products.data ?? []).flatMap((p) =>
      p.skus.map((s) => ({
        value: s.id,
        label: `${p.name} · ${s.pack_label}`,
        category: p.category,
      })),
    );
    const localName = (x: { name: string; names: Record<string, string> }) =>
      x.names[locale] ?? x.name;
    const cropList = crops.data ?? [];
    const pestList = pests.data ?? [];
    return {
      skus,
      crops: cropList,
      pests: pestList,
      skuLabel: (id) => skus.find((s) => s.value === id)?.label ?? id,
      cropLabel: (id) => {
        const c = cropList.find((x) => x.id === id);
        return c ? localName(c) : id;
      },
      pestLabel: (id) => {
        const p = pestList.find((x) => x.id === id);
        return p ? localName(p) : id;
      },
      loading: products.isPending || crops.isPending || pests.isPending,
      error: products.error ?? crops.error ?? pests.error,
    };
  }, [
    products.data,
    products.isPending,
    products.error,
    crops.data,
    crops.isPending,
    crops.error,
    pests.data,
    pests.isPending,
    pests.error,
    locale,
  ]);
}

function LabelClaimsContent() {
  const t = useT();
  const { role, user } = useSession();
  const maintainer = can(role, CLAIM_EDIT_ROLES);
  const [status, setStatus] = React.useState<ClaimStatus | "all">(maintainer ? "all" : "approved");
  const [cropId, setCropId] = React.useState("");
  const [pestId, setPestId] = React.useState("");
  const [skuId, setSkuId] = React.useState("");
  const [editor, setEditor] = React.useState<{ open: boolean; claim?: LabelClaim }>({
    open: false,
  });
  const [approving, setApproving] = React.useState<LabelClaim | null>(null);
  const [retiring, setRetiring] = React.useState<LabelClaim | null>(null);
  const [historyOf, setHistoryOf] = React.useState<LabelClaim | null>(null);

  const lookups = useLookups();
  const claims = useLabelClaims({
    status: maintainer ? status : "approved",
    crop_id: cropId || undefined,
    pest_id: pestId || undefined,
    sku_id: skuId || undefined,
  });

  const pestOptions = lookups.pests
    .filter((p) => !cropId || p.crop_id === null || p.crop_id === cropId)
    .map((p) => ({ value: p.id, label: lookups.pestLabel(p.id) }));

  const columns: DataTableColumn<LabelClaim>[] = [
    {
      id: "sku",
      header: t("claims.fields.sku"),
      accessor: (c) => lookups.skuLabel(c.sku_id),
      sortable: true,
    },
    {
      id: "crop",
      header: t("claims.fields.crop"),
      accessor: (c) => lookups.cropLabel(c.crop_id),
      sortable: true,
    },
    {
      id: "pest",
      header: t("claims.fields.pest"),
      accessor: (c) => lookups.pestLabel(c.pest_or_disease_id),
      sortable: true,
    },
    { id: "dose", header: t("claims.columns.dose"), accessor: (c) => c.dose_per_acre },
    {
      id: "tank",
      header: t("claims.columns.tank"),
      accessor: (c) => c.dose_per_tank_15l ?? t("common.none"),
    },
    {
      id: "phi",
      header: t("claims.columns.phi"),
      numeric: true,
      accessor: (c) => c.phi_days ?? -1,
      cell: (c) => (c.phi_days === null ? t("common.none") : t("claims.days", { n: c.phi_days })),
      sortable: true,
    },
    {
      id: "status",
      header: t("claims.columns.status"),
      accessor: (c) => c.status,
      cell: (c) => <ClaimStatusChip status={c.status} />,
      sortable: true,
    },
    {
      id: "actions",
      header: t("claims.columns.actions"),
      cell: (c) => (
        <span className="flex flex-wrap gap-1" data-testid={`claim-actions-${c.id}`}>
          {can(role, CLAIM_EDIT_ROLES) && c.status !== "retired" ? (
            <AppButton
              variant="tertiary"
              icon={<Pencil />}
              aria-label={t("claims.edit")}
              title={t("claims.edit")}
              onClick={() => setEditor({ open: true, claim: c })}
            />
          ) : null}
          {can(role, CLAIM_APPROVE_ROLES) && c.status === "draft" ? (
            <AppButton variant="secondary" icon={<CheckCircle2 />} onClick={() => setApproving(c)}>
              {t("claims.approve")}
            </AppButton>
          ) : null}
          {can(role, CLAIM_RETIRE_ROLES) && c.status !== "retired" ? (
            <AppButton variant="tertiary" icon={<Archive />} onClick={() => setRetiring(c)}>
              {t("claims.retire")}
            </AppButton>
          ) : null}
          {maintainer ? (
            <AppButton
              variant="tertiary"
              icon={<History />}
              aria-label={t("claims.history")}
              title={t("claims.history")}
              onClick={() => setHistoryOf(c)}
            />
          ) : null}
        </span>
      ),
    },
  ];

  const filtered = !!(cropId || pestId || skuId || (maintainer && status !== "all"));
  const loadError = claims.error ?? lookups.error;

  return (
    <div className="grid grid-cols-1 gap-4 xl:grid-cols-[1fr_22rem]">
      <div className="flex min-w-0 flex-col gap-4">
        <div
          role="group"
          aria-label={t("filterBar.label")}
          data-testid="filter-bar"
          className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3"
        >
          <SelectField
            label={t("claims.fields.crop")}
            value={cropId}
            onChange={(e) => {
              setCropId(e.target.value);
              setPestId("");
            }}
            emptyLabel={t("common.all")}
            options={lookups.crops.map((c) => ({ value: c.id, label: lookups.cropLabel(c.id) }))}
            className="w-40"
          />
          <SelectField
            label={t("claims.fields.pest")}
            value={pestId}
            onChange={(e) => setPestId(e.target.value)}
            emptyLabel={t("common.all")}
            options={pestOptions}
            className="w-48"
          />
          <SelectField
            label={t("claims.fields.sku")}
            value={skuId}
            onChange={(e) => setSkuId(e.target.value)}
            emptyLabel={t("common.all")}
            options={lookups.skus}
            className="w-56"
          />
          {maintainer ? (
            <SelectField
              label={t("claims.columns.status")}
              value={status}
              onChange={(e) => setStatus(e.target.value as ClaimStatus | "all")}
              options={[
                { value: "all", label: t("common.all") },
                ...CLAIM_STATUSES.map((s) => ({ value: s, label: t(`claims.status.${s}`) })),
              ]}
              className="w-40"
              testId="claim-status-filter"
            />
          ) : null}
          {can(role, CLAIM_EDIT_ROLES) ? (
            <AppButton
              className="ml-auto"
              icon={<Plus />}
              onClick={() => setEditor({ open: true })}
            >
              {t("claims.newClaim")}
            </AppButton>
          ) : null}
        </div>

        <DataTable
          columns={columns}
          rows={claims.data ?? []}
          rowKey={(c) => c.id}
          loading={claims.isPending || lookups.loading}
          error={loadError ? problemMessage(loadError, t) : undefined}
          onRetry={() => void claims.refetch()}
          caption={t("claims.title")}
          emptyTitle={filtered ? t("claims.emptyFilteredTitle") : t("claims.emptyTitle")}
          emptyHelp={filtered ? t("claims.emptyFiltered") : t("claims.emptyHelp")}
        />
      </div>

      <RecommendationPreview lookups={lookups} />

      <ClaimEditorDialog
        open={editor.open}
        claim={editor.claim}
        lookups={lookups}
        onOpenChange={(open) => setEditor((s) => ({ ...s, open }))}
      />
      <ApproveDialog
        claim={approving}
        lookups={lookups}
        approverName={user?.name ?? ""}
        onOpenChange={(open) => (open ? null : setApproving(null))}
      />
      <RetireDialog
        claim={retiring}
        lookups={lookups}
        onOpenChange={(open) => (open ? null : setRetiring(null))}
      />
      <HistoryDrawer
        claim={historyOf}
        lookups={lookups}
        onOpenChange={(open) => (open ? null : setHistoryOf(null))}
      />
    </div>
  );
}

/**
 * "Preview recommendation": what DX-007 may recommend for a crop and problem. Backed by
 * `GET /v1/catalog/recommendable` (the guardrail function) — only SKUs with an approved label
 * claim for exactly that crop and pest, with the label dose, PHI and PPE (SPEC 3.4).
 */
function RecommendationPreview({ lookups }: { lookups: Lookups }) {
  const t = useT();
  const [cropId, setCropId] = React.useState("");
  const [pestId, setPestId] = React.useState("");
  const rec = useRecommendable(cropId || undefined, pestId || undefined);
  const pestOptions = lookups.pests
    .filter((p) => !cropId || p.crop_id === null || p.crop_id === cropId)
    .map((p) => ({ value: p.id, label: lookups.pestLabel(p.id) }));

  return (
    <section
      aria-labelledby="rec-preview-title"
      className="flex h-fit flex-col gap-3 rounded-card border border-border bg-surface p-4"
      data-testid="recommendation-preview"
    >
      <h2 id="rec-preview-title" className="text-heading font-semibold">
        {t("claims.preview.title")}
      </h2>
      <p className="text-small text-text-secondary">{t("claims.preview.help")}</p>
      <SelectField
        label={t("claims.fields.crop")}
        value={cropId}
        onChange={(e) => {
          setCropId(e.target.value);
          setPestId("");
        }}
        emptyLabel={t("claims.fields.choose")}
        options={lookups.crops.map((c) => ({ value: c.id, label: lookups.cropLabel(c.id) }))}
        testId="preview-crop"
      />
      <SelectField
        label={t("claims.fields.pest")}
        value={pestId}
        onChange={(e) => setPestId(e.target.value)}
        emptyLabel={t("claims.fields.choose")}
        options={pestOptions}
        testId="preview-pest"
      />
      {!cropId || !pestId ? (
        <EmptyState help={t("claims.preview.pick")} className="py-6" />
      ) : rec.isPending ? (
        <SkeletonText lines={3} />
      ) : rec.isError ? (
        <ErrorState detail={problemMessage(rec.error, t)} onRetry={() => void rec.refetch()} />
      ) : rec.data.length === 0 ? (
        <EmptyState
          title={t("claims.preview.noneTitle")}
          help={t("claims.preview.none")}
          className="py-6"
        />
      ) : (
        <ul className="flex flex-col gap-2">
          {rec.data.map((r) => (
            <li
              key={r.label_claim_id}
              className="flex flex-col gap-1 rounded-card border border-border p-3"
              data-testid="recommendable-sku"
            >
              <span className="flex flex-wrap items-center gap-2 font-semibold">
                {r.product_name} · {r.pack_label}
                {r.own_brand ? <OwnBrandBadge compact /> : null}
              </span>
              <span className="text-small text-text-secondary">
                {t("claims.preview.dose", {
                  dose: r.dose_per_acre,
                  tank: r.dose_per_tank_15l ?? t("common.none"),
                })}
              </span>
              <span className="text-small text-text-secondary">
                {r.phi_days === null
                  ? t("claims.preview.phiUnknown")
                  : t("claims.preview.phi", { n: r.phi_days })}
                {" · "}
                {formatInr(r.mrp_paise)}
              </span>
              {r.ppe_text ? (
                <span className="text-small">{t("claims.preview.ppe", { ppe: r.ppe_text })}</span>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
