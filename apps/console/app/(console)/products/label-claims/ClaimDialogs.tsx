"use client";

import * as React from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { AppTextField } from "@/components/ds/AppTextField";
import { Dialog } from "@/components/ds/Dialog";
import { EmptyState } from "@/components/ds/EmptyState";
import { ErrorState } from "@/components/ds/ErrorState";
import { SkeletonText } from "@/components/ds/Skeleton";
import { toast } from "@/components/ds/Toasts";
import {
  Dialog as DialogRoot,
  DialogContent,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import {
  DOSE_UNITS,
  type Crop,
  type LabelClaim,
  type PestOrDisease,
  type ProductCategory,
} from "@/lib/catalog";
import { makeClaimSchema, toClaimInput, type ClaimFormValues } from "@/lib/catalog-schemas";
import { formatDateTimeIst } from "@/lib/format";
import {
  useApproveClaim,
  useClaimHistory,
  useCreateClaim,
  useRetireClaim,
  useUpdateClaim,
} from "@/lib/hooks/catalog";
import { useT } from "@/lib/i18n-client";
import { fieldErrors, problemCode, problemMessage } from "@/lib/problem-messages";
import { useFieldError } from "../_components/ProductDialogs";
import { ClaimStatusChip, SelectField, TextAreaField } from "../_components/fields";

export interface SkuOption {
  value: string;
  label: string;
  category: ProductCategory;
}

export interface Lookups {
  skus: ReadonlyArray<SkuOption>;
  crops: ReadonlyArray<Crop>;
  pests: ReadonlyArray<PestOrDisease>;
  skuLabel: (id: string) => string;
  cropLabel: (id: string) => string;
  pestLabel: (id: string) => string;
}

const claimDefaults = (c?: LabelClaim): ClaimFormValues => ({
  sku_id: c?.sku_id ?? "",
  crop_id: c?.crop_id ?? "",
  pest_or_disease_id: c?.pest_or_disease_id ?? "",
  dose_per_acre: c?.dose_per_acre ?? "",
  dose_value: c?.dose_value ? String(Number(c.dose_value)) : "",
  dose_unit: c?.dose_unit ?? "ml",
  dose_per_tank_15l: c?.dose_per_tank_15l ?? "",
  phi_days: c?.phi_days !== null && c?.phi_days !== undefined ? String(c.phi_days) : "",
  ppe_text: c?.ppe_text ?? "",
  safety_text: c?.safety_text ?? "",
  source_ref: c?.source_ref ?? "",
  efficacy_tier: c?.efficacy_tier ? String(c.efficacy_tier) : "",
});

/** C51 editor: create a draft, edit a draft, or (approved) save a new draft version. */
export function ClaimEditorDialog({
  open,
  onOpenChange,
  claim,
  lookups,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  claim?: LabelClaim;
  lookups: Lookups;
}) {
  const t = useT();
  const fe = useFieldError();
  const create = useCreateClaim();
  const update = useUpdateClaim();
  const [error, setError] = React.useState<string>();
  const schema = React.useMemo(
    () =>
      makeClaimSchema({
        pests: lookups.pests,
        skuCategory: (id) => lookups.skus.find((s) => s.value === id)?.category,
      }),
    [lookups.pests, lookups.skus],
  );
  const form = useForm<ClaimFormValues>({
    resolver: zodResolver(schema),
    defaultValues: claimDefaults(claim),
  });
  const { register, handleSubmit, reset, formState, watch, setError: setFieldError } = form;

  React.useEffect(() => {
    if (open) {
      reset(claimDefaults(claim));
      setError(undefined);
    }
  }, [open, claim, reset]);

  const cropId = watch("crop_id");
  const pestOptions = lookups.pests
    .filter((p) => !cropId || p.crop_id === null || p.crop_id === cropId)
    .map((p) => ({ value: p.id, label: lookups.pestLabel(p.id) }));

  const submit = handleSubmit(async (values) => {
    setError(undefined);
    const input = toClaimInput(values);
    try {
      if (claim) {
        const { sku_id: _s, crop_id: _c, pest_or_disease_id: _p, ...patch } = input;
        void _s;
        void _c;
        void _p;
        const saved = await update.mutateAsync({
          id: claim.id,
          body: { ...patch, version: claim.version },
        });
        toast.success(saved.id !== claim.id ? t("claims.newVersionSaved") : t("claims.saved"));
      } else {
        await create.mutateAsync(input);
        toast.success(t("claims.draftCreated"));
      }
      onOpenChange(false);
    } catch (err) {
      const code = problemCode(err);
      if (code === "pest_not_for_crop")
        setFieldError("pest_or_disease_id", { message: "problems.pestNotForCrop" });
      if (code === "claim_category_invalid")
        setFieldError("sku_id", { message: "problems.claimCategoryInvalid" });
      if (code === "claim_duplicate")
        setFieldError("pest_or_disease_id", { message: "problems.claimDuplicate" });
      const fields = fieldErrors(err);
      for (const f of [
        "dose_value",
        "dose_unit",
        "phi_days",
        "source_ref",
        "dose_per_acre",
      ] as const)
        if (fields[f]) setFieldError(f, { message: fields[f] });
      setError(problemMessage(err, t));
    }
  });

  const e = formState.errors;
  const locked = !!claim;
  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={claim ? t("claims.editTitle") : t("claims.newTitle")}
      description={
        claim?.status === "approved" ? t("claims.editApprovedHelp") : t("claims.editorHelp")
      }
      confirmLabel={claim ? t("common.save") : t("claims.saveDraft")}
      onConfirm={() => void submit()}
      loading={create.isPending || update.isPending}
      error={error}
      className="max-h-[90vh] max-w-3xl overflow-y-auto"
    >
      <form
        onSubmit={(ev) => {
          ev.preventDefault();
          void submit();
        }}
        className="grid grid-cols-1 gap-3 sm:grid-cols-3"
        data-testid="claim-form"
        noValidate
      >
        <SelectField
          label={t("claims.fields.sku")}
          emptyLabel={t("claims.fields.choose")}
          options={lookups.skus}
          disabled={locked}
          error={fe(e.sku_id?.message)}
          className="sm:col-span-3"
          testId="claim-sku"
          {...register("sku_id")}
        />
        <SelectField
          label={t("claims.fields.crop")}
          emptyLabel={t("claims.fields.choose")}
          options={lookups.crops.map((c) => ({ value: c.id, label: lookups.cropLabel(c.id) }))}
          disabled={locked}
          error={fe(e.crop_id?.message)}
          testId="claim-crop"
          {...register("crop_id")}
        />
        <SelectField
          label={t("claims.fields.pest")}
          emptyLabel={t("claims.fields.choose")}
          options={pestOptions}
          disabled={locked}
          error={fe(e.pest_or_disease_id?.message)}
          className="sm:col-span-2"
          testId="claim-pest"
          {...register("pest_or_disease_id")}
        />
        <AppTextField
          label={t("claims.fields.dosePerAcre")}
          helper={t("claims.fields.dosePerAcreHelp")}
          error={fe(e.dose_per_acre?.message)}
          {...register("dose_per_acre")}
        />
        <AppTextField
          label={t("claims.fields.doseValue")}
          inputMode="decimal"
          error={fe(e.dose_value?.message)}
          {...register("dose_value")}
        />
        <SelectField
          label={t("claims.fields.doseUnit")}
          options={DOSE_UNITS.map((u) => ({ value: u, label: u }))}
          error={fe(e.dose_unit?.message)}
          {...register("dose_unit")}
        />
        <AppTextField
          label={t("claims.fields.dosePerTank")}
          optional
          error={fe(e.dose_per_tank_15l?.message)}
          {...register("dose_per_tank_15l")}
        />
        <AppTextField
          label={t("claims.fields.phi")}
          inputMode="numeric"
          error={fe(e.phi_days?.message)}
          {...register("phi_days")}
        />
        <SelectField
          label={t("claims.fields.tier")}
          emptyLabel={t("common.none")}
          options={["1", "2", "3"].map((v) => ({ value: v, label: v }))}
          error={fe(e.efficacy_tier?.message)}
          {...register("efficacy_tier")}
        />
        <TextAreaField
          label={t("claims.fields.ppe")}
          optional
          className="sm:col-span-3"
          error={fe(e.ppe_text?.message)}
          {...register("ppe_text")}
        />
        <TextAreaField
          label={t("claims.fields.safety")}
          optional
          className="sm:col-span-3"
          error={fe(e.safety_text?.message)}
          {...register("safety_text")}
        />
        <AppTextField
          label={t("claims.fields.sourceRef")}
          helper={t("claims.fields.sourceRefHelp")}
          className="sm:col-span-3"
          error={fe(e.source_ref?.message)}
          {...register("source_ref")}
        />
        <button type="submit" hidden />
      </form>
    </Dialog>
  );
}

/** Human gate (SPEC 14.6): only the agronomist approves; the API records who and when. */
export function ApproveDialog({
  claim,
  onOpenChange,
  lookups,
  approverName,
}: {
  claim: LabelClaim | null;
  onOpenChange: (open: boolean) => void;
  lookups: Lookups;
  approverName: string;
}) {
  const t = useT();
  const approve = useApproveClaim();
  const [error, setError] = React.useState<string>();
  React.useEffect(() => setError(undefined), [claim]);
  return (
    <Dialog
      open={!!claim}
      onOpenChange={onOpenChange}
      title={t("claims.approveTitle")}
      description={t("claims.approveRegulatory", { name: approverName })}
      confirmLabel={t("claims.approveConfirm")}
      loading={approve.isPending}
      error={error}
      onConfirm={() => {
        if (!claim) return;
        setError(undefined);
        approve.mutate(claim.id, {
          onSuccess: () => {
            toast.success(t("claims.approved"));
            onOpenChange(false);
          },
          onError: (err) => setError(problemMessage(err, t)),
        });
      }}
    >
      {claim ? <ClaimSummary claim={claim} lookups={lookups} /> : null}
    </Dialog>
  );
}

export function RetireDialog({
  claim,
  onOpenChange,
  lookups,
}: {
  claim: LabelClaim | null;
  onOpenChange: (open: boolean) => void;
  lookups: Lookups;
}) {
  const t = useT();
  const retire = useRetireClaim();
  const [error, setError] = React.useState<string>();
  React.useEffect(() => setError(undefined), [claim]);
  return (
    <Dialog
      open={!!claim}
      onOpenChange={onOpenChange}
      title={t("claims.retireTitle")}
      description={t("claims.retireHelp")}
      confirmLabel={t("claims.retireConfirm")}
      destructive
      loading={retire.isPending}
      error={error}
      onConfirm={() => {
        if (!claim) return;
        setError(undefined);
        retire.mutate(claim.id, {
          onSuccess: () => {
            toast.success(t("claims.retired"));
            onOpenChange(false);
          },
          onError: (err) => setError(problemMessage(err, t)),
        });
      }}
    >
      {claim ? <ClaimSummary claim={claim} lookups={lookups} /> : null}
    </Dialog>
  );
}

function ClaimSummary({ claim, lookups }: { claim: LabelClaim; lookups: Lookups }) {
  const t = useT();
  const rows: Array<[string, string]> = [
    [t("claims.fields.sku"), lookups.skuLabel(claim.sku_id)],
    [t("claims.fields.crop"), lookups.cropLabel(claim.crop_id)],
    [t("claims.fields.pest"), lookups.pestLabel(claim.pest_or_disease_id)],
    [t("claims.fields.dosePerAcre"), claim.dose_per_acre],
    [t("claims.fields.dosePerTank"), claim.dose_per_tank_15l ?? t("common.none")],
    [
      t("claims.fields.phi"),
      claim.phi_days === null ? t("common.none") : t("claims.days", { n: claim.phi_days }),
    ],
    [t("claims.fields.sourceRef"), claim.source_ref],
  ];
  return (
    <dl
      className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-small"
      data-testid="claim-summary"
    >
      {rows.map(([k, v]) => (
        <React.Fragment key={k}>
          <dt className="font-semibold text-text-secondary">{k}</dt>
          <dd className="break-words">{v}</dd>
        </React.Fragment>
      ))}
    </dl>
  );
}

/** Version history drawer: every version of the claim chain, newest first. */
export function HistoryDrawer({
  claim,
  onOpenChange,
  lookups,
}: {
  claim: LabelClaim | null;
  onOpenChange: (open: boolean) => void;
  lookups: Lookups;
}) {
  const t = useT();
  const history = useClaimHistory(claim?.id ?? null);
  return (
    <DialogRoot open={!!claim} onOpenChange={onOpenChange}>
      <DialogContent
        closeLabel={t("dialog.close")}
        className="left-auto right-0 top-0 h-full max-w-md translate-x-0 translate-y-0 content-start overflow-y-auto rounded-none"
        data-testid="history-drawer"
      >
        <DialogTitle>{t("claims.historyTitle")}</DialogTitle>
        <DialogDescription>
          {claim
            ? `${lookups.skuLabel(claim.sku_id)} · ${lookups.cropLabel(claim.crop_id)} · ${lookups.pestLabel(claim.pest_or_disease_id)}`
            : null}
        </DialogDescription>
        {history.isPending ? (
          <SkeletonText lines={4} />
        ) : history.isError ? (
          <ErrorState
            detail={problemMessage(history.error, t)}
            onRetry={() => void history.refetch()}
          />
        ) : history.data.length === 0 ? (
          <EmptyState help={t("claims.historyEmpty")} />
        ) : (
          <ol className="flex flex-col gap-3">
            {history.data.map((v, i) => (
              <li
                key={v.id}
                className="flex flex-col gap-1 rounded-card border border-border p-3"
                data-testid="history-version"
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="text-small font-semibold">
                    {t("claims.versionN", { n: history.data.length - i })}
                  </span>
                  <ClaimStatusChip status={v.status} />
                </div>
                <p className="text-small">
                  {v.dose_per_acre} · {v.dose_per_tank_15l ?? t("common.none")} ·{" "}
                  {v.phi_days === null ? t("common.none") : t("claims.days", { n: v.phi_days })}
                </p>
                <p className="text-small text-text-muted">
                  {t("claims.createdAt", { at: formatDateTimeIst(v.created_at) })}
                </p>
                {v.approved_at ? (
                  <p className="text-small text-text-muted">
                    {t("claims.approvedAt", { at: formatDateTimeIst(v.approved_at) })}
                  </p>
                ) : null}
                {v.retired_at ? (
                  <p className="text-small text-text-muted">
                    {t("claims.retiredAt", { at: formatDateTimeIst(v.retired_at) })}
                  </p>
                ) : null}
              </li>
            ))}
          </ol>
        )}
      </DialogContent>
    </DialogRoot>
  );
}
