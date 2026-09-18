"use client";

import * as React from "react";
import { Pencil, Plus, Save, X } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { ErrorState } from "@/components/ds/ErrorState";
import { toast } from "@/components/ds/Toasts";
import { Input } from "@/components/ui/input";
import {
  CATALOG_WRITE_ROLES,
  PRICE_READ_ROLES,
  can,
  paiseToRupees,
  rupeesToPaise,
  type PriceRow,
  type PriceRowInput,
  type PriceRowProblem,
} from "@/lib/catalog";
import { validatePriceRow, type PriceDraft } from "@/lib/catalog-schemas";
import { ApiError } from "@/lib/api";
import { formatDateIst, formatInr } from "@/lib/format";
import { usePriceLists, useProducts, usePutPriceLists, useStores } from "@/lib/hooks/catalog";
import type { MessageKey } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";
import {
  PageHeader,
  ProductsSubNav,
  SelectField,
  SessionGate,
  selectClass,
} from "../_components/fields";

/** C52 Price lists (WC-005 "price lists by store"). */
export function PricesView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C52">
      <PageHeader title={t("prices.title")} subtitle={t("prices.subtitle")} />
      <ProductsSubNav />
      <SessionGate>
        <PricesGate />
      </SessionGate>
    </div>
  );
}

function PricesGate() {
  const t = useT();
  const { role } = useSession();
  if (!can(role, PRICE_READ_ROLES))
    return <ErrorState title={t("problems.forbidden")} help={t("prices.forbiddenHelp")} />;
  return <PricesContent />;
}

interface Line {
  key: string;
  sku_id: string;
  existing?: PriceRow;
}

interface Edit extends PriceDraft {
  sku_id: string;
}

const todayIso = () => new Date().toISOString().slice(0, 10);

function PricesContent() {
  const t = useT();
  const { role } = useSession();
  const canWrite = can(role, CATALOG_WRITE_ROLES);
  const [storeId, setStoreId] = React.useState<string>("");
  const stores = useStores();
  const products = useProducts({ include_inactive: true });
  const prices = usePriceLists(storeId || null);
  const put = usePutPriceLists();
  const [edits, setEdits] = React.useState<Record<string, Edit>>({});
  const [added, setAdded] = React.useState<string[]>([]);
  const [rowErrors, setRowErrors] = React.useState<Record<string, MessageKey>>({});
  const [error, setError] = React.useState<string>();
  const seq = React.useRef(0);

  React.useEffect(() => {
    setEdits({});
    setAdded([]);
    setRowErrors({});
    setError(undefined);
  }, [storeId]);

  const skuIndex = React.useMemo(() => {
    const m = new Map<string, { label: string; mrp: number }>();
    for (const p of products.data ?? [])
      for (const s of p.skus)
        m.set(s.id, { label: `${p.name} · ${s.pack_label}`, mrp: s.mrp_paise });
    return m;
  }, [products.data]);
  const skuOptions = [...skuIndex.entries()].map(([value, v]) => ({ value, label: v.label }));

  const lines: Line[] = [
    ...added.map((key) => ({ key, sku_id: edits[key]?.sku_id ?? "" })),
    ...(prices.data ?? []).map((row) => ({ key: row.id, sku_id: row.sku_id, existing: row })),
  ];

  const startEdit = (line: Line) => {
    const row = line.existing;
    if (!row) return;
    setEdits((e) => ({
      ...e,
      [line.key]: {
        sku_id: row.sku_id,
        price: paiseToRupees(row.price_paise),
        effective_from: row.effective_from,
        effective_to: row.effective_to ?? "",
      },
    }));
  };
  const cancelEdit = (key: string) => {
    setEdits(({ [key]: _gone, ...rest }) => rest);
    setAdded((a) => a.filter((k) => k !== key));
    setRowErrors(({ [key]: _gone, ...rest }) => rest);
  };
  const addLine = () => {
    seq.current += 1;
    const key = `new-${seq.current}`;
    setAdded((a) => [key, ...a]);
    setEdits((e) => ({
      ...e,
      [key]: { sku_id: "", price: "", effective_from: todayIso(), effective_to: "" },
    }));
  };
  const change = (key: string, patch: Partial<Edit>) =>
    setEdits((e) => {
      const cur = e[key];
      return cur ? { ...e, [key]: { ...cur, ...patch } } : e;
    });

  const mrpOf = (skuId: string) => skuIndex.get(skuId)?.mrp;
  const pending = Object.entries(edits);

  const save = async () => {
    setError(undefined);
    const errs: Record<string, MessageKey> = {};
    for (const [key, edit] of pending) {
      const mrp = mrpOf(edit.sku_id);
      if (!edit.sku_id || mrp === undefined) {
        errs[key] = "validation.required";
        continue;
      }
      const problem = validatePriceRow(edit, mrp);
      if (problem) errs[key] = problem;
    }
    setRowErrors(errs);
    if (Object.keys(errs).length) return;
    const keys = pending.map(([key]) => key);
    const items: PriceRowInput[] = pending.map(([, e]) => ({
      sku_id: e.sku_id,
      price_paise: rupeesToPaise(e.price) ?? 0,
      effective_from: e.effective_from,
      effective_to: e.effective_to === "" ? null : e.effective_to,
    }));
    try {
      await put.mutateAsync({ storeId: storeId || null, items });
      toast.success(t("prices.saved"));
      setEdits({});
      setAdded([]);
    } catch (err) {
      const rows =
        err instanceof ApiError ? (err.problem.rows as PriceRowProblem[] | undefined) : undefined;
      if (rows?.length) {
        const mapped: Record<string, MessageKey> = {};
        for (const r of rows) {
          const key = keys[r.index];
          if (key)
            mapped[key] =
              r.code === "price_above_mrp" ? "problems.priceAboveMrp" : "problems.priceOverlap";
        }
        setRowErrors(mapped);
      }
      setError(problemMessage(err, t));
    }
  };

  const cellInput = (
    key: string,
    field: keyof PriceDraft,
    type: string,
    label: string,
    disabled = false,
  ) => (
    <Input
      type={type}
      aria-label={label}
      value={edits[key]?.[field] ?? ""}
      disabled={disabled}
      aria-invalid={rowErrors[key] ? true : undefined}
      inputMode={field === "price" ? "decimal" : undefined}
      onChange={(e) => change(key, { [field]: e.target.value })}
      className="h-9 min-w-[7rem]"
      data-testid={`price-${field}-${key}`}
    />
  );

  const columns: DataTableColumn<Line>[] = [
    {
      id: "sku",
      header: t("prices.columns.sku"),
      cell: (l) =>
        l.existing ? (
          (skuIndex.get(l.sku_id)?.label ?? l.sku_id)
        ) : (
          <select
            aria-label={t("prices.columns.sku")}
            className={cn(selectClass, "h-9 min-w-[14rem]")}
            value={edits[l.key]?.sku_id ?? ""}
            onChange={(e) => change(l.key, { sku_id: e.target.value })}
            data-testid={`price-sku-${l.key}`}
          >
            <option value="">{t("claims.fields.choose")}</option>
            {skuOptions.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        ),
    },
    {
      id: "mrp",
      header: t("prices.columns.mrp"),
      numeric: true,
      cell: (l) => {
        const mrp = l.existing?.mrp_paise ?? mrpOf(edits[l.key]?.sku_id ?? "");
        return mrp === undefined ? t("common.none") : formatInr(mrp);
      },
    },
    {
      id: "price",
      header: t("prices.columns.price"),
      numeric: true,
      cell: (l) =>
        edits[l.key]
          ? cellInput(l.key, "price", "text", t("prices.columns.price"))
          : l.existing
            ? formatInr(l.existing.price_paise)
            : null,
    },
    {
      id: "from",
      header: t("prices.columns.from"),
      cell: (l) =>
        edits[l.key]
          ? cellInput(l.key, "effective_from", "date", t("prices.columns.from"), !!l.existing)
          : l.existing
            ? formatDateIst(l.existing.effective_from)
            : null,
    },
    {
      id: "to",
      header: t("prices.columns.to"),
      cell: (l) =>
        edits[l.key]
          ? cellInput(l.key, "effective_to", "date", t("prices.columns.to"))
          : l.existing?.effective_to
            ? formatDateIst(l.existing.effective_to)
            : t("prices.openEnded"),
    },
    {
      id: "state",
      header: t("prices.columns.state"),
      cell: (l) =>
        rowErrors[l.key] ? (
          <span
            role="alert"
            className="text-small text-danger"
            data-testid={`price-error-${l.key}`}
          >
            {t(rowErrors[l.key] as MessageKey)}
          </span>
        ) : edits[l.key] ? (
          <span className="text-small text-warning">{t("prices.unsaved")}</span>
        ) : null,
    },
    ...(canWrite
      ? [
          {
            id: "actions",
            header: t("prices.columns.actions"),
            cell: (l: Line) =>
              edits[l.key] ? (
                <AppButton
                  variant="tertiary"
                  icon={<X />}
                  aria-label={t("common.cancel")}
                  title={t("common.cancel")}
                  onClick={() => cancelEdit(l.key)}
                />
              ) : (
                <AppButton
                  variant="tertiary"
                  icon={<Pencil />}
                  aria-label={t("prices.edit")}
                  title={t("prices.edit")}
                  onClick={() => startEdit(l)}
                  data-testid={`price-edit-${l.key}`}
                />
              ),
          } satisfies DataTableColumn<Line>,
        ]
      : []),
  ];

  const loadError = prices.error ?? products.error ?? stores.error;

  return (
    <>
      <div
        role="group"
        aria-label={t("filterBar.label")}
        data-testid="filter-bar"
        className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3"
      >
        <SelectField
          label={t("prices.store")}
          value={storeId}
          onChange={(e) => setStoreId(e.target.value)}
          options={[
            { value: "", label: t("prices.tenantDefault") },
            ...(stores.data ?? []).map((s) => ({ value: s.id, label: `${s.name} (${s.code})` })),
          ]}
          className="w-64"
          testId="price-store"
        />
        {canWrite ? (
          <div className="ml-auto flex flex-wrap gap-2">
            <AppButton variant="secondary" icon={<Plus />} onClick={addLine}>
              {t("prices.addRow")}
            </AppButton>
            <AppButton
              icon={<Save />}
              onClick={() => void save()}
              disabled={pending.length === 0}
              loading={put.isPending}
              data-testid="price-save"
            >
              {t("prices.saveChanges", { n: pending.length })}
            </AppButton>
          </div>
        ) : null}
      </div>
      {error ? (
        <p role="alert" className="text-small text-danger" data-testid="price-save-error">
          {error}
        </p>
      ) : null}
      <p className="text-small text-text-muted">{t("prices.rule")}</p>
      <DataTable
        columns={columns}
        rows={lines}
        rowKey={(l) => l.key}
        loading={prices.isPending || products.isPending}
        error={loadError ? problemMessage(loadError, t) : undefined}
        onRetry={() => void prices.refetch()}
        caption={t("prices.title")}
        emptyTitle={t("prices.emptyTitle")}
        emptyHelp={storeId ? t("prices.emptyStore") : t("prices.emptyDefault")}
      />
    </>
  );
}
