"use client";

/**
 * WC-008 segment builder with the live consented count, shared by C81 (campaign builder) and
 * C32 (farmer segments). The count is always presented as "farmers with marketing consent" and
 * the excluded-for-consent number is shown next to it: consent is not a criterion the console
 * can switch off, and `consentNote()` decides the wording (lib/campaigns.ts, unit-tested).
 */
import * as React from "react";
import { ShieldCheck, Users } from "lucide-react";
import { Skeleton } from "@/components/ds/Skeleton";
import { AppButton } from "@/components/ds/AppButton";
import { CROP_STAGES } from "@/lib/analytics";
import { consentNote, isEmptySegment, type CampaignSegment } from "@/lib/campaigns";
import { formatNumber } from "@/lib/format";
import { useFilterOptions } from "@/lib/hooks/analytics";
import { useSegmentCount } from "@/lib/hooks/growth";
import { LOCALE_OPTIONS } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { CheckboxList, Choice, NumberField, Note } from "./common";

export interface SegmentBuilderProps {
  value: CampaignSegment;
  onChange: (next: CampaignSegment) => void;
  /** Extra controls under the count (e.g. "Create a campaign from this segment"). */
  actions?: React.ReactNode;
  error?: string;
  /** The consented count, whenever it changes (null while unknown) — C81 splits the arms with it. */
  onCount?: (count: number | null) => void;
}

const RUPEES = 100;

export function SegmentBuilder({ value, onChange, actions, error, onCount }: SegmentBuilderProps) {
  const t = useT();
  const opts = useFilterOptions();
  const empty = isEmptySegment(value);
  const count = useSegmentCount(value, !empty);

  const reported = count.data && !empty ? count.data.count : null;
  React.useEffect(() => {
    onCount?.(reported);
  }, [reported, onCount]);

  const patch = (next: Partial<CampaignSegment>) => {
    const merged = { ...value, ...next };
    for (const [k, v] of Object.entries(merged))
      if (v === undefined || (Array.isArray(v) && v.length === 0))
        delete merged[k as keyof CampaignSegment];
    onChange(merged);
  };

  const districts = [...new Set(opts.stores.map((s) => s.district).filter(Boolean))].sort();

  return (
    <div className="flex flex-col gap-3" data-testid="segment-builder">
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <CheckboxList
          label={t("campaigns.segment.crops")}
          testId="segment-crops"
          options={opts.crops.map((c) => ({ value: c.id, label: c.name }))}
          selected={value.crop_ids ?? []}
          onChange={(crop_ids) => patch({ crop_ids })}
        />
        <CheckboxList
          label={t("campaigns.segment.stages")}
          testId="segment-stages"
          options={CROP_STAGES.map((s) => ({ value: s, label: t(`stage.${s}`) }))}
          selected={value.stages ?? []}
          onChange={(stages) => patch({ stages })}
        />
        <CheckboxList
          label={t("campaigns.segment.districts")}
          testId="segment-districts"
          options={districts.map((d) => ({ value: d, label: d }))}
          selected={value.districts ?? []}
          onChange={(ds) => patch({ districts: ds })}
        />
        <CheckboxList
          label={t("campaigns.segment.languages")}
          testId="segment-languages"
          options={LOCALE_OPTIONS.map((l) => ({ value: l.locale, label: l.nativeName }))}
          selected={value.languages ?? []}
          onChange={(languages) => patch({ languages })}
        />
      </div>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <NumberField
          id="seg-purchase"
          label={t("campaigns.segment.purchaseWithin")}
          value={value.purchase_within_days}
          min={1}
          onChange={(purchase_within_days) =>
            patch({ purchase_within_days, no_purchase_within_days: undefined })
          }
        />
        <NumberField
          id="seg-spend"
          label={t("campaigns.segment.minSpend")}
          value={value.min_spend_paise === undefined ? undefined : value.min_spend_paise / RUPEES}
          min={0}
          onChange={(rupees) =>
            patch({ min_spend_paise: rupees === undefined ? undefined : rupees * RUPEES })
          }
        />
        <NumberField
          id="seg-nopurchase"
          label={t("campaigns.segment.noPurchaseWithin")}
          value={value.no_purchase_within_days}
          min={1}
          onChange={(no_purchase_within_days) =>
            patch({ no_purchase_within_days, purchase_within_days: undefined })
          }
        />
        <NumberField
          id="seg-visited"
          label={t("campaigns.segment.visitedWithin")}
          value={value.visited_within_days}
          min={1}
          onChange={(visited_within_days) =>
            patch({ visited_within_days, not_visited_within_days: undefined })
          }
        />
        <NumberField
          id="seg-notvisited"
          label={t("campaigns.segment.notVisitedWithin")}
          value={value.not_visited_within_days}
          min={1}
          onChange={(not_visited_within_days) =>
            patch({ not_visited_within_days, visited_within_days: undefined })
          }
        />
        <Choice
          id="seg-appuser"
          label={t("campaigns.segment.appUser")}
          value={value.app_user === undefined ? "" : value.app_user ? "yes" : "no"}
          options={[
            { value: "yes", label: t("common.yes") },
            { value: "no", label: t("common.no") },
          ]}
          includeAll
          onChange={(v) => patch({ app_user: v === "" ? undefined : v === "yes" })}
        />
        <NumberField
          id="seg-appactive"
          label={t("campaigns.segment.appActiveWithin")}
          value={value.app_active_within_days}
          min={1}
          onChange={(app_active_within_days) => patch({ app_active_within_days })}
        />
        <NumberField
          id="seg-minacres"
          label={t("campaigns.segment.minAcres")}
          value={value.min_acres}
          min={0}
          onChange={(min_acres) => patch({ min_acres })}
        />
        <NumberField
          id="seg-maxacres"
          label={t("campaigns.segment.maxAcres")}
          value={value.max_acres}
          min={0}
          onChange={(max_acres) => patch({ max_acres })}
        />
        <div className="flex items-end">
          <AppButton variant="tertiary" onClick={() => onChange({})} disabled={empty}>
            {t("campaigns.segment.clear")}
          </AppButton>
        </div>
      </div>

      {error ? (
        <p className="text-small text-danger" role="alert" data-testid="segment-error">
          {error}
        </p>
      ) : null}

      <section
        className="flex flex-col gap-2 rounded-card border border-border bg-surface p-4"
        data-testid="consent-count"
      >
        <h3 className="flex items-center gap-2 text-heading font-semibold">
          <Users className="size-5 text-primary" aria-hidden="true" />
          {t("campaigns.consent.badge")}
        </h3>
        {empty ? (
          <p className="text-body text-text-secondary" data-testid="consent-empty">
            {t("campaigns.segment.pickCriterion")}
          </p>
        ) : count.isLoading && !count.data ? (
          <Skeleton announce className="h-6 w-64" />
        ) : count.error ? (
          <p className="text-body text-danger" role="alert">
            {t("analytics.errorTitle")}
          </p>
        ) : (
          <p
            className="text-body text-text"
            data-testid="consent-line"
            aria-live="polite"
            data-count={count.data?.count ?? 0}
          >
            {(() => {
              const note = consentNote(count.data);
              return t(`campaigns.consent.${note.key}`, {
                count: formatNumber(note.params.count),
                excluded: formatNumber(note.params.excluded),
              });
            })()}
          </p>
        )}
        <Note icon={<ShieldCheck className="size-4" aria-hidden="true" />} testId="consent-always">
          {t("campaigns.consent.always")}
        </Note>
        {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
      </section>
    </div>
  );
}
