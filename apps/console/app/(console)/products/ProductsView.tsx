"use client";

import * as React from "react";
import { ChevronDown, ChevronRight, Download, Pencil, Plus, Upload } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { AppTextField } from "@/components/ds/AppTextField";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { OwnBrandBadge } from "@/components/ds/OwnBrandBadge";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import {
  CATALOG_WRITE_ROLES,
  EXPORT_ROLES,
  PRODUCT_CATEGORIES,
  can,
  catalog,
  downloadText,
  type Product,
  type ProductCategory,
  type ProductWithSkus,
  type Sku,
} from "@/lib/catalog";
import { formatInr } from "@/lib/format";
import { useProducts } from "@/lib/hooks/catalog";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";
import { PageHeader, ProductsSubNav, SelectField, SessionGate } from "./_components/fields";
import { ImportDialog } from "./_components/ImportDialog";
import { ProductDialog, SkuDialog } from "./_components/ProductDialogs";

type Row =
  | { kind: "product"; product: ProductWithSkus }
  | { kind: "sku"; product: ProductWithSkus; sku: Sku };

type ActiveFilter = "active" | "inactive" | "all";

/** C50 Product master (WC-005). */
export function ProductsView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C50">
      <PageHeader title={t("products.title")} subtitle={t("products.subtitle")} />
      <ProductsSubNav />
      <SessionGate>
        <ProductsContent />
      </SessionGate>
    </div>
  );
}

function ProductsContent() {
  const t = useT();
  const { role } = useSession();
  const canWrite = can(role, CATALOG_WRITE_ROLES);
  const [q, setQ] = React.useState("");
  const [search, setSearch] = React.useState("");
  const [category, setCategory] = React.useState<ProductCategory | "">("");
  const [ownBrand, setOwnBrand] = React.useState<"" | "true" | "false">("");
  const [active, setActive] = React.useState<ActiveFilter>("active");
  const [expanded, setExpanded] = React.useState<Set<string>>(new Set());
  const [productDialog, setProductDialog] = React.useState<{ open: boolean; product?: Product }>({
    open: false,
  });
  const [skuDialog, setSkuDialog] = React.useState<{ open: boolean; product?: Product; sku?: Sku }>(
    { open: false },
  );
  const [importOpen, setImportOpen] = React.useState(false);
  const [exporting, setExporting] = React.useState(false);

  React.useEffect(() => {
    const id = setTimeout(() => setSearch(q.trim()), 300);
    return () => clearTimeout(id);
  }, [q]);

  const query = useProducts({
    q: search || undefined,
    category: category || undefined,
    own_brand: ownBrand === "" ? undefined : ownBrand === "true",
    include_inactive: active !== "active",
  });
  const products = React.useMemo(
    () => (query.data ?? []).filter((p) => (active === "inactive" ? !p.active : true)),
    [query.data, active],
  );

  const rows: Row[] = React.useMemo(
    () =>
      products.flatMap((product) => [
        { kind: "product" as const, product },
        ...(expanded.has(product.id)
          ? product.skus.map((sku) => ({ kind: "sku" as const, product, sku }))
          : []),
      ]),
    [products, expanded],
  );

  const toggle = (id: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const onExport = async () => {
    setExporting(true);
    try {
      downloadText("products.csv", await catalog.exportCsv("products"));
    } catch (err) {
      toast.error(problemMessage(err, t));
    } finally {
      setExporting(false);
    }
  };

  const columns: DataTableColumn<Row>[] = [
    {
      id: "expand",
      header: "",
      width: "2.5rem",
      cell: (r) =>
        r.kind === "product" ? (
          <button
            type="button"
            onClick={() => toggle(r.product.id)}
            aria-expanded={expanded.has(r.product.id)}
            aria-label={
              expanded.has(r.product.id)
                ? t("products.collapseSkus", { name: r.product.name })
                : t("products.expandSkus", { name: r.product.name })
            }
            className="rounded-input p-1 text-text-muted hover:text-text"
          >
            {expanded.has(r.product.id) ? (
              <ChevronDown className="size-4" aria-hidden="true" />
            ) : (
              <ChevronRight className="size-4" aria-hidden="true" />
            )}
          </button>
        ) : null,
    },
    {
      id: "name",
      header: t("products.columns.name"),
      cell: (r) =>
        r.kind === "product" ? (
          <span className="flex flex-wrap items-center gap-2 font-semibold">
            {r.product.name}
            {r.product.own_brand ? <OwnBrandBadge compact /> : null}
          </span>
        ) : (
          <span className="pl-4 text-text-secondary" data-testid="sku-row">
            {r.sku.pack_label}
          </span>
        ),
    },
    {
      id: "brand",
      header: t("products.columns.brand"),
      cell: (r) => (r.kind === "product" ? r.product.brand : null),
    },
    {
      id: "category",
      header: t("products.columns.category"),
      cell: (r) => (r.kind === "product" ? t(`products.categories.${r.product.category}`) : null),
    },
    {
      id: "tax",
      header: t("products.columns.tax"),
      cell: (r) =>
        r.kind === "product" ? (
          <span className="tnum">
            {r.product.hsn ?? t("common.none")} · {r.product.gst_rate_bp / 100} %
          </span>
        ) : null,
    },
    {
      id: "skus",
      header: t("products.columns.skus"),
      cell: (r) =>
        r.kind === "product" ? (
          <span className="tnum">{r.product.skus.length}</span>
        ) : (
          <span className="tnum text-small">{r.sku.barcode ?? t("common.none")}</span>
        ),
    },
    {
      id: "mrp",
      header: t("products.columns.mrpPrice"),
      numeric: true,
      cell: (r) =>
        r.kind === "sku" ? (
          <span className="tnum">
            {formatInr(r.sku.mrp_paise)} / {formatInr(r.sku.price_paise)}
          </span>
        ) : null,
    },
    {
      id: "status",
      header: t("products.columns.status"),
      cell: (r) => {
        const on = r.kind === "product" ? r.product.active : r.sku.active;
        return (
          <Badge variant={on ? "success" : "neutral"}>
            {on ? t("products.active") : t("products.inactive")}
          </Badge>
        );
      },
    },
    ...(canWrite
      ? [
          {
            id: "actions",
            header: t("products.columns.actions"),
            cell: (r: Row) =>
              r.kind === "product" ? (
                <span className="flex gap-1">
                  <AppButton
                    variant="tertiary"
                    size="M"
                    icon={<Pencil />}
                    aria-label={t("products.editNamed", { name: r.product.name })}
                    onClick={() => setProductDialog({ open: true, product: r.product })}
                  />
                  <AppButton
                    variant="tertiary"
                    size="M"
                    icon={<Plus />}
                    aria-label={t("products.addSkuNamed", { name: r.product.name })}
                    onClick={() => setSkuDialog({ open: true, product: r.product })}
                  />
                </span>
              ) : (
                <AppButton
                  variant="tertiary"
                  size="M"
                  icon={<Pencil />}
                  aria-label={t("products.editSkuNamed", { name: r.sku.pack_label })}
                  onClick={() => setSkuDialog({ open: true, product: r.product, sku: r.sku })}
                />
              ),
          } satisfies DataTableColumn<Row>,
        ]
      : []),
  ];

  const filtered = !!(search || category || ownBrand || active !== "active");

  return (
    <>
      <div
        role="group"
        aria-label={t("filterBar.label")}
        data-testid="filter-bar"
        className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3"
      >
        <AppTextField
          label={t("common.search")}
          placeholder={t("products.searchPlaceholder")}
          value={q}
          onChange={(e) => setQ(e.target.value)}
          className="min-w-[14rem] flex-1"
          type="search"
        />
        <SelectField
          label={t("products.columns.category")}
          value={category}
          onChange={(e) => setCategory(e.target.value as ProductCategory | "")}
          emptyLabel={t("common.all")}
          options={PRODUCT_CATEGORIES.map((c) => ({
            value: c,
            label: t(`products.categories.${c}`),
          }))}
          className="w-44"
        />
        <SelectField
          label={t("products.filters.ownBrand")}
          value={ownBrand}
          onChange={(e) => setOwnBrand(e.target.value as "" | "true" | "false")}
          emptyLabel={t("common.all")}
          options={[
            { value: "true", label: t("products.filters.ownBrandOnly") },
            { value: "false", label: t("products.filters.multiBrand") },
          ]}
          className="w-44"
        />
        <SelectField
          label={t("products.filters.active")}
          value={active}
          onChange={(e) => setActive(e.target.value as ActiveFilter)}
          options={[
            { value: "active", label: t("products.filters.activeOnly") },
            { value: "inactive", label: t("products.filters.inactiveOnly") },
            { value: "all", label: t("common.all") },
          ]}
          className="w-44"
        />
        <div className="ml-auto flex flex-wrap items-center gap-2">
          {can(role, EXPORT_ROLES) ? (
            <AppButton
              variant="secondary"
              icon={<Download />}
              onClick={() => void onExport()}
              loading={exporting}
              data-testid="export-products"
            >
              {t("common.export")}
            </AppButton>
          ) : null}
          {canWrite ? (
            <>
              <AppButton variant="secondary" icon={<Upload />} onClick={() => setImportOpen(true)}>
                {t("import.action")}
              </AppButton>
              <AppButton icon={<Plus />} onClick={() => setProductDialog({ open: true })}>
                {t("products.newProduct")}
              </AppButton>
            </>
          ) : null}
        </div>
      </div>

      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => (r.kind === "product" ? r.product.id : `${r.product.id}/${r.sku.id}`)}
        loading={query.isPending}
        error={query.isError ? problemMessage(query.error, t) : undefined}
        onRetry={() => void query.refetch()}
        caption={t("products.title")}
        emptyTitle={filtered ? t("products.emptyFilteredTitle") : t("products.emptyTitle")}
        emptyHelp={filtered ? t("products.emptyFiltered") : t("products.emptyHelp")}
        className={cn(query.isFetching && !query.isPending && "opacity-80")}
      />

      <ProductDialog
        open={productDialog.open}
        product={productDialog.product}
        onOpenChange={(open) => setProductDialog((s) => ({ ...s, open }))}
      />
      {skuDialog.product ? (
        <SkuDialog
          open={skuDialog.open}
          product={skuDialog.product}
          sku={skuDialog.sku}
          onOpenChange={(open) => setSkuDialog((s) => ({ ...s, open }))}
        />
      ) : null}
      <ImportDialog open={importOpen} onOpenChange={setImportOpen} kind="products" />
    </>
  );
}
