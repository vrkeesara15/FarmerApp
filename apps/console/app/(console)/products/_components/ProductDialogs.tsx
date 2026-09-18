"use client";

import * as React from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { AppTextField } from "@/components/ds/AppTextField";
import { Dialog } from "@/components/ds/Dialog";
import { toast } from "@/components/ds/Toasts";
import {
  GST_RATES_BP,
  PACK_UNITS,
  PRODUCT_CATEGORIES,
  paiseToRupees,
  type Product,
  type Sku,
} from "@/lib/catalog";
import {
  productSchema,
  skuSchema,
  toProductInput,
  toSkuInput,
  type ProductFormValues,
  type SkuFormValues,
} from "@/lib/catalog-schemas";
import {
  useCreateProduct,
  useCreateSku,
  useUpdateProduct,
  useUpdateSku,
} from "@/lib/hooks/catalog";
import type { MessageKey } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { fieldErrors, problemCode, problemMessage } from "@/lib/problem-messages";
import { CheckboxField, SelectField } from "./fields";

/** Zod messages are message keys; unknown text (server `msg`) is shown as is. */
export function useFieldError() {
  const t = useT();
  return (message: string | undefined) =>
    message === undefined ? undefined : message.includes(".") ? t(message as MessageKey) : message;
}

const productDefaults = (p?: Product): ProductFormValues => ({
  name: p?.name ?? "",
  brand: p?.brand ?? "",
  own_brand: p?.own_brand ?? false,
  category: p?.category ?? "pesticide",
  hsn: p?.hsn ?? "",
  gst_rate_bp: String(p?.gst_rate_bp ?? 1800),
  active_ingredient: p?.active_ingredient ?? "",
  formulation: p?.formulation ?? "",
  active: p?.active ?? true,
});

export function ProductDialog({
  open,
  onOpenChange,
  product,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Edit this product; create when undefined. */
  product?: Product;
}) {
  const t = useT();
  const fe = useFieldError();
  const create = useCreateProduct();
  const update = useUpdateProduct();
  const [error, setError] = React.useState<string>();
  const form = useForm<ProductFormValues>({
    resolver: zodResolver(productSchema),
    defaultValues: productDefaults(product),
  });
  const { register, handleSubmit, reset, formState, setError: setFieldError } = form;

  React.useEffect(() => {
    if (open) {
      reset(productDefaults(product));
      setError(undefined);
    }
  }, [open, product, reset]);

  const busy = create.isPending || update.isPending;
  const submit = handleSubmit(async (values) => {
    setError(undefined);
    const body = toProductInput(values);
    try {
      if (product)
        await update.mutateAsync({ id: product.id, body: { ...body, version: product.version } });
      else await create.mutateAsync(body);
      toast.success(t("products.saved"));
      onOpenChange(false);
    } catch (err) {
      const code = problemCode(err);
      if (code === "product_exists") setFieldError("name", { message: "problems.productExists" });
      const fields = fieldErrors(err);
      for (const f of ["gst_rate_bp", "hsn", "name", "brand", "category"] as const)
        if (fields[f]) setFieldError(f, { message: fields[f] });
      setError(problemMessage(err, t));
    }
  });

  const e = formState.errors;
  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={product ? t("products.editProduct") : t("products.newProduct")}
      confirmLabel={t("common.save")}
      onConfirm={() => void submit()}
      loading={busy}
      error={error}
      className="max-w-2xl"
    >
      <form
        onSubmit={(ev) => {
          ev.preventDefault();
          void submit();
        }}
        className="grid grid-cols-1 gap-3 sm:grid-cols-2"
        data-testid="product-form"
        noValidate
      >
        <AppTextField
          label={t("products.fields.name")}
          error={fe(e.name?.message)}
          {...register("name")}
        />
        <AppTextField
          label={t("products.fields.brand")}
          error={fe(e.brand?.message)}
          {...register("brand")}
        />
        <SelectField
          label={t("products.fields.category")}
          error={fe(e.category?.message)}
          options={PRODUCT_CATEGORIES.map((c) => ({
            value: c,
            label: t(`products.categories.${c}`),
          }))}
          {...register("category")}
        />
        <SelectField
          label={t("products.fields.gst")}
          error={fe(e.gst_rate_bp?.message)}
          options={GST_RATES_BP.map((bp) => ({ value: String(bp), label: `${bp / 100} %` }))}
          {...register("gst_rate_bp")}
        />
        <AppTextField
          label={t("products.fields.hsn")}
          helper={t("products.fields.hsnHelp")}
          optional
          inputMode="numeric"
          error={fe(e.hsn?.message)}
          {...register("hsn")}
        />
        <AppTextField
          label={t("products.fields.formulation")}
          optional
          error={fe(e.formulation?.message)}
          {...register("formulation")}
        />
        <AppTextField
          className="sm:col-span-2"
          label={t("products.fields.activeIngredient")}
          optional
          error={fe(e.active_ingredient?.message)}
          {...register("active_ingredient")}
        />
        <CheckboxField label={t("products.fields.ownBrand")} {...register("own_brand")} />
        <CheckboxField label={t("products.fields.active")} {...register("active")} />
        <button type="submit" hidden />
      </form>
    </Dialog>
  );
}

const skuDefaults = (s?: Sku): SkuFormValues => ({
  pack_size_value: s ? String(Number(s.pack_size_value)) : "",
  pack_size_unit: s?.pack_size_unit ?? "ml",
  barcode: s?.barcode ?? "",
  mrp: s ? paiseToRupees(s.mrp_paise) : "",
  active: s?.active ?? true,
});

export function SkuDialog({
  open,
  onOpenChange,
  product,
  sku,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  product: Product;
  /** Edit this SKU; create when undefined. */
  sku?: Sku;
}) {
  const t = useT();
  const fe = useFieldError();
  const create = useCreateSku();
  const update = useUpdateSku();
  const [error, setError] = React.useState<string>();
  const form = useForm<SkuFormValues>({
    resolver: zodResolver(skuSchema),
    defaultValues: skuDefaults(sku),
  });
  const { register, handleSubmit, reset, formState, setError: setFieldError } = form;

  React.useEffect(() => {
    if (open) {
      reset(skuDefaults(sku));
      setError(undefined);
    }
  }, [open, sku, reset]);

  const submit = handleSubmit(async (values) => {
    setError(undefined);
    const input = toSkuInput(product.id, values);
    try {
      if (sku) {
        const { product_id: _ignored, ...body } = input;
        void _ignored;
        await update.mutateAsync({ id: sku.id, body: { ...body, version: sku.version } });
      } else await create.mutateAsync(input);
      toast.success(t("products.saved"));
      onOpenChange(false);
    } catch (err) {
      if (problemCode(err) === "barcode_exists")
        setFieldError("barcode", { message: "problems.barcodeExists" });
      setError(problemMessage(err, t));
    }
  });

  const e = formState.errors;
  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={sku ? t("products.editSku") : t("products.addSku")}
      description={`${product.brand} · ${product.name}`}
      confirmLabel={t("common.save")}
      onConfirm={() => void submit()}
      loading={create.isPending || update.isPending}
      error={error}
    >
      <form
        onSubmit={(ev) => {
          ev.preventDefault();
          void submit();
        }}
        className="grid grid-cols-2 gap-3"
        data-testid="sku-form"
        noValidate
      >
        <AppTextField
          label={t("products.fields.packSize")}
          inputMode="decimal"
          error={fe(e.pack_size_value?.message)}
          {...register("pack_size_value")}
        />
        <SelectField
          label={t("products.fields.packUnit")}
          error={fe(e.pack_size_unit?.message)}
          options={PACK_UNITS.map((u) => ({ value: u, label: u }))}
          {...register("pack_size_unit")}
        />
        <AppTextField
          label={t("products.fields.barcode")}
          optional
          inputMode="numeric"
          error={fe(e.barcode?.message)}
          {...register("barcode")}
        />
        <AppTextField
          label={t("products.fields.mrp")}
          prefix="₹"
          inputMode="decimal"
          error={fe(e.mrp?.message)}
          {...register("mrp")}
        />
        <CheckboxField label={t("products.fields.active")} {...register("active")} />
        <button type="submit" hidden />
      </form>
    </Dialog>
  );
}
