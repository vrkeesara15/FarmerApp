"use client";

/**
 * WC-009 incentive rule editor: eligibility, components (slabs, per-unit, percent, threshold,
 * with per-component caps), attainment multipliers, the total cap and the clawback switch.
 * Money is entered in rupees and kept in integer paise (CLAUDE.md). `validateDefinition()`
 * (lib/incentives.ts, unit-tested) blocks publishing a document the engine would refuse.
 */
import * as React from "react";
import { Plus, Trash2 } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { CheckboxField } from "@/components/admin/common";
import {
  COMPONENT_KINDS,
  PAISE_METRICS,
  RULE_METRICS,
  validateDefinition,
  type ComponentKind,
  type RuleComponent,
  type RuleDefinition,
  type RuleIssue,
  type RuleMetric,
} from "@/lib/incentives";
import { useT } from "@/lib/i18n-client";
import { Choice, NumberField, TextField } from "./common";

const RUPEES = 100;
const toRupees = (paise: number | null | undefined) =>
  paise === null || paise === undefined ? undefined : paise / RUPEES;
const toPaise = (rupees: number | undefined) =>
  rupees === undefined ? undefined : Math.round(rupees * RUPEES);

export function RuleIssues({ issues }: { issues: RuleIssue[] }) {
  const t = useT();
  if (issues.length === 0) return null;
  return (
    <div
      className="rounded-card border border-danger bg-danger-container p-3 text-small text-danger"
      role="alert"
      data-testid="rule-issues"
    >
      <p className="font-semibold">{t("incentives.ruleError.title")}</p>
      <ul className="list-inside list-disc">
        {issues.map((i, idx) => (
          <li key={`${i.component ?? "doc"}-${i.code}-${idx}`}>
            {t(`incentives.ruleError.${i.code}` as "incentives.ruleError.noComponents")}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function RuleEditor({
  value,
  onChange,
  disabled,
}: {
  value: RuleDefinition;
  onChange: (next: RuleDefinition) => void;
  disabled?: boolean;
}) {
  const t = useT();
  const patch = (next: Partial<RuleDefinition>) => onChange({ ...value, ...next });
  const setComponent = (index: number, next: RuleComponent) =>
    patch({ components: value.components.map((c, i) => (i === index ? next : c)) });

  return (
    <div className="flex flex-col gap-4" data-testid="rule-editor">
      <section className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
        <h3 className="text-heading font-semibold">{t("incentives.rules.eligibility")}</h3>
        <div className="grid gap-3 md:grid-cols-2">
          <NumberField
            id="rule-min-visits"
            label={t("incentives.rules.minVisits")}
            value={value.eligibility?.min_verified_visits}
            min={0}
            disabled={disabled}
            onChange={(v) =>
              patch({ eligibility: { ...value.eligibility, min_verified_visits: v } })
            }
          />
          <TextField
            id="rule-statuses"
            label={t("incentives.rules.countStatuses")}
            value={(value.eligibility?.count_visit_statuses ?? ["verified"]).join(", ")}
            disabled={disabled}
            onChange={(raw) =>
              patch({
                eligibility: {
                  ...value.eligibility,
                  count_visit_statuses: raw
                    .split(",")
                    .map((s) => s.trim())
                    .filter(Boolean),
                },
              })
            }
          />
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-heading font-semibold">{t("incentives.rules.components")}</h3>
          <AppButton
            variant="secondary"
            disabled={disabled}
            onClick={() =>
              patch({
                components: [
                  ...value.components,
                  {
                    id: `component_${value.components.length + 1}`,
                    metric: "verified_visits",
                    kind: "per_unit",
                    rate_paise: 0,
                  },
                ],
              })
            }
            data-testid="add-component"
          >
            <Plus className="size-4" aria-hidden="true" />
            {t("incentives.rules.addComponent")}
          </AppButton>
        </div>
        {value.components.map((c, i) => (
          <ComponentRow
            key={i}
            component={c}
            index={i}
            disabled={disabled}
            onChange={(next) => setComponent(i, next)}
            onRemove={() => patch({ components: value.components.filter((_, j) => j !== i) })}
          />
        ))}
      </section>

      <section className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-heading font-semibold">{t("incentives.rules.multipliers")}</h3>
          <AppButton
            variant="secondary"
            disabled={disabled}
            onClick={() =>
              patch({
                multipliers: [
                  ...(value.multipliers ?? []),
                  { metric: "attainment.sales_paise", gte: 1, factor: 1.1 },
                ],
              })
            }
          >
            <Plus className="size-4" aria-hidden="true" />
            {t("incentives.rules.addMultiplier")}
          </AppButton>
        </div>
        {(value.multipliers ?? []).map((m, i) => (
          <div key={i} className="grid gap-3 md:grid-cols-4">
            <Choice
              id={`multiplier-metric-${i}`}
              label={t("incentives.rules.multiplierMetric")}
              value={m.metric}
              disabled={disabled}
              options={RULE_METRICS.flatMap((metric) => [
                {
                  value: `attainment.${metric}`,
                  label: `${t(`incentives.rules.metrics.${metric}`)} %`,
                },
                { value: metric as string, label: t(`incentives.rules.metrics.${metric}`) },
              ])}
              onChange={(metric) =>
                patch({
                  multipliers: (value.multipliers ?? []).map((x, j) =>
                    j === i ? { ...x, metric: metric || x.metric } : x,
                  ),
                })
              }
            />
            <NumberField
              id={`multiplier-gte-${i}`}
              label={t("incentives.rules.multiplierGte")}
              value={m.gte}
              step={0.05}
              disabled={disabled}
              onChange={(gte) =>
                patch({
                  multipliers: (value.multipliers ?? []).map((x, j) =>
                    j === i ? { ...x, gte: gte ?? 0 } : x,
                  ),
                })
              }
            />
            <NumberField
              id={`multiplier-factor-${i}`}
              label={t("incentives.rules.multiplierFactor")}
              value={m.factor}
              step={0.05}
              disabled={disabled}
              onChange={(factor) =>
                patch({
                  multipliers: (value.multipliers ?? []).map((x, j) =>
                    j === i ? { ...x, factor: factor ?? 0 } : x,
                  ),
                })
              }
            />
            <div className="flex items-end">
              <AppButton
                variant="tertiary"
                disabled={disabled}
                onClick={() =>
                  patch({ multipliers: (value.multipliers ?? []).filter((_, j) => j !== i) })
                }
              >
                <Trash2 className="size-4" aria-hidden="true" />
                {t("incentives.rules.removeComponent")}
              </AppButton>
            </div>
          </div>
        ))}
      </section>

      <section className="grid gap-3 rounded-card border border-border bg-surface p-4 md:grid-cols-2">
        <NumberField
          id="rule-cap"
          label={t("incentives.rules.totalCap")}
          value={toRupees(value.cap_paise)}
          min={0}
          disabled={disabled}
          onChange={(v) => patch({ cap_paise: toPaise(v) ?? null })}
        />
        <div className="flex items-end">
          <CheckboxField
            label={t("incentives.rules.clawback")}
            checked={value.clawback?.cancelled_orders === true}
            disabled={disabled}
            onChange={(e) => patch({ clawback: { cancelled_orders: e.target.checked } })}
          />
        </div>
      </section>
    </div>
  );
}

function ComponentRow({
  component: c,
  index,
  onChange,
  onRemove,
  disabled,
}: {
  component: RuleComponent;
  index: number;
  onChange: (next: RuleComponent) => void;
  onRemove: () => void;
  disabled?: boolean;
}) {
  const t = useT();
  const set = (next: Partial<RuleComponent>) => onChange({ ...c, ...next });
  const slabs = c.slabs ?? [];
  const isSlab = c.kind === "slab_per_unit" || c.kind === "slab_flat";

  return (
    <div
      className="flex flex-col gap-3 rounded-card border border-border p-3"
      data-testid={`component-${index}`}
    >
      <div className="grid gap-3 md:grid-cols-4">
        <TextField
          id={`component-id-${index}`}
          label={t("incentives.rules.componentId")}
          value={c.id}
          disabled={disabled}
          onChange={(id) => set({ id })}
        />
        <Choice
          id={`component-metric-${index}`}
          label={t("incentives.rules.metric")}
          value={c.metric as RuleMetric}
          disabled={disabled}
          options={RULE_METRICS.map((m) => ({
            value: m,
            label: t(`incentives.rules.metrics.${m}`),
          }))}
          onChange={(metric) => set({ metric: metric || c.metric })}
        />
        <Choice
          id={`component-kind-${index}`}
          label={t("incentives.rules.kind")}
          value={c.kind}
          disabled={disabled}
          options={COMPONENT_KINDS.map((k) => ({
            value: k,
            label: t(`incentives.rules.kinds.${k}`),
          }))}
          onChange={(kind) =>
            set({
              kind: (kind || c.kind) as ComponentKind,
              slabs:
                kind === "slab_per_unit" || kind === "slab_flat"
                  ? (c.slabs ?? [{ from: 0, rate_paise: 0 }])
                  : undefined,
            })
          }
        />
        <div className="flex items-end">
          <AppButton variant="tertiary" onClick={onRemove} disabled={disabled}>
            <Trash2 className="size-4" aria-hidden="true" />
            {t("incentives.rules.removeComponent")}
          </AppButton>
        </div>
      </div>

      <div className="grid gap-3 md:grid-cols-4">
        {c.kind === "per_unit" ? (
          <NumberField
            id={`component-rate-${index}`}
            label={t("incentives.rules.rate")}
            value={toRupees(c.rate_paise)}
            min={0}
            disabled={disabled}
            onChange={(v) => set({ rate_paise: toPaise(v) ?? 0 })}
          />
        ) : null}
        {c.kind === "percent" ? (
          <NumberField
            id={`component-ratebp-${index}`}
            label={t("incentives.rules.rateBp")}
            value={c.rate_bp}
            min={1}
            disabled={disabled}
            onChange={(rate_bp) => set({ rate_bp })}
          />
        ) : null}
        {c.kind === "threshold" ? (
          <>
            <NumberField
              id={`component-threshold-${index}`}
              label={t("incentives.rules.threshold")}
              value={c.threshold}
              step={PAISE_METRICS.includes(c.metric) ? 1 : 0.05}
              disabled={disabled}
              onChange={(threshold) => set({ threshold })}
            />
            <NumberField
              id={`component-amount-${index}`}
              label={t("incentives.rules.amount")}
              value={toRupees(c.amount_paise)}
              min={0}
              disabled={disabled}
              onChange={(v) => set({ amount_paise: toPaise(v) ?? 0 })}
            />
          </>
        ) : null}
        <NumberField
          id={`component-cap-${index}`}
          label={t("incentives.rules.cap")}
          value={toRupees(c.cap_paise)}
          min={0}
          disabled={disabled}
          onChange={(v) => set({ cap_paise: toPaise(v) ?? null })}
        />
      </div>

      {isSlab ? (
        <div className="flex flex-col gap-2">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="text-small font-semibold text-text-secondary">
              {t("incentives.rules.slabs")}
            </span>
            <AppButton
              variant="secondary"
              disabled={disabled}
              onClick={() => {
                const last = slabs[slabs.length - 1];
                const from = last?.to ?? (last ? last.from + 1 : 0);
                const next = slabs.map((s, i) =>
                  i === slabs.length - 1 && s.to == null ? { ...s, to: from } : s,
                );
                set({
                  slabs: [
                    ...next,
                    c.kind === "slab_per_unit"
                      ? { from, rate_paise: 0 }
                      : { from, amount_paise: 0 },
                  ],
                });
              }}
              data-testid={`add-slab-${index}`}
            >
              <Plus className="size-4" aria-hidden="true" />
              {t("incentives.rules.addSlab")}
            </AppButton>
          </div>
          {slabs.map((s, si) => (
            <div key={si} className="grid gap-3 md:grid-cols-4">
              <NumberField
                id={`slab-from-${index}-${si}`}
                label={t("incentives.rules.slabFrom")}
                value={s.from}
                min={0}
                disabled={disabled}
                onChange={(from) =>
                  set({ slabs: slabs.map((x, j) => (j === si ? { ...x, from: from ?? 0 } : x)) })
                }
              />
              <NumberField
                id={`slab-to-${index}-${si}`}
                label={
                  si === slabs.length - 1
                    ? t("incentives.rules.slabOpen")
                    : t("incentives.rules.slabTo")
                }
                value={s.to ?? undefined}
                min={0}
                disabled={disabled}
                onChange={(to) =>
                  set({ slabs: slabs.map((x, j) => (j === si ? { ...x, to: to ?? null } : x)) })
                }
              />
              <NumberField
                id={`slab-amount-${index}-${si}`}
                label={
                  c.kind === "slab_per_unit"
                    ? t("incentives.rules.rate")
                    : t("incentives.rules.amount")
                }
                value={toRupees(c.kind === "slab_per_unit" ? s.rate_paise : s.amount_paise)}
                min={0}
                disabled={disabled}
                onChange={(v) =>
                  set({
                    slabs: slabs.map((x, j) =>
                      j === si
                        ? c.kind === "slab_per_unit"
                          ? { ...x, rate_paise: toPaise(v) ?? 0 }
                          : { ...x, amount_paise: toPaise(v) ?? 0 }
                        : x,
                    ),
                  })
                }
              />
              <div className="flex items-end">
                <AppButton
                  variant="tertiary"
                  disabled={disabled || slabs.length === 1}
                  onClick={() => set({ slabs: slabs.filter((_, j) => j !== si) })}
                >
                  <Trash2 className="size-4" aria-hidden="true" />
                  {t("incentives.rules.removeComponent")}
                </AppButton>
              </div>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}

export { validateDefinition };
