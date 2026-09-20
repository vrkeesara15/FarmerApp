"use client";

/**
 * C81 campaign builder (WC-008): segment with the live consented count, channel, one message
 * per language with a phone preview, holdout percentage, conversion window and the schedule.
 *
 * Save draft -> `POST /v1/campaigns`; Schedule -> `POST /v1/campaigns/{id}/schedule`, which
 * freezes the consented audience and the holdout split on the server. Validation mirrors
 * `validateDraft()` (lib/campaigns.ts) so the screen never posts a document the API refuses.
 */
import * as React from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ArrowLeft, CalendarClock, Save } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { Skeleton } from "@/components/ds/Skeleton";
import { toast } from "@/components/ds/Toasts";
import { PageHeader } from "@/components/analytics/Page";
import { QueryError, RoleGate, SessionGate } from "@/components/admin/common";
import {
  CAMPAIGN_CHANNELS,
  CAMPAIGN_WRITE_ROLES,
  filledLanguages,
  MESSAGE_MAX_CHARS,
  sendAtToIso,
  splitArms,
  validateDraft,
  type CampaignChannel,
  type CampaignDraft,
  type CampaignSegment,
  type DraftIssue,
} from "@/lib/campaigns";
import { formatNumber } from "@/lib/format";
import {
  useCampaign,
  useCreateCampaign,
  useScheduleCampaign,
  useUpdateCampaign,
} from "@/lib/hooks/growth";
import { LOCALE_OPTIONS, type Locale } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { Choice, LinkButton, NumberField, Note, TextField } from "./common";
import { PhonePreview } from "./PhonePreview";
import { SegmentBuilder } from "./SegmentBuilder";
import { readStoredSegment } from "./SegmentsView";

const EMPTY: CampaignDraft = {
  name: "",
  channel: "sms",
  segment: {},
  messages: {},
  holdout_pct: 10,
  attribution_days: 14,
  send_at: null,
};

export function CampaignBuilder() {
  return (
    <div className="flex flex-col gap-4" data-screen="C81">
      <SessionGate>
        <RoleGate roles={CAMPAIGN_WRITE_ROLES}>
          <Builder />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function issueFor(issues: DraftIssue[], field: DraftIssue["field"]): string | undefined {
  return issues.find((i) => i.field === field)?.code;
}

function Builder() {
  const t = useT();
  const router = useRouter();
  const params = useSearchParams();
  const editId = params?.get("id") ?? null;
  const existing = useCampaign(editId ?? "", !!editId);

  const [draft, setDraft] = React.useState<CampaignDraft>(EMPTY);
  const [previewLanguage, setPreviewLanguage] = React.useState<Locale>("en");
  const [showIssues, setShowIssues] = React.useState(false);
  const [error, setError] = React.useState<string | undefined>();
  const loadedId = React.useRef<string | null>(null);

  // A segment handed over by C32 (?from=segment) seeds the builder once.
  const fromSegment = params?.get("from") === "segment";
  const seeded = React.useRef(false);
  React.useEffect(() => {
    if (!fromSegment || seeded.current) return;
    seeded.current = true;
    const stored = readStoredSegment();
    if (stored) setDraft((d) => ({ ...d, segment: stored }));
  }, [fromSegment]);

  // A draft opened from C80 (or created here) fills the form once.
  React.useEffect(() => {
    const c = existing.data;
    if (!c || loadedId.current === c.id) return;
    loadedId.current = c.id;
    setDraft({
      name: c.name,
      channel: c.channel,
      segment: c.segment,
      messages: c.messages as Partial<Record<Locale, string>>,
      holdout_pct: c.holdout_pct,
      attribution_days: c.attribution_days,
      send_at: null,
    });
  }, [existing.data]);

  const create = useCreateCampaign();
  const update = useUpdateCampaign();
  const schedule = useScheduleCampaign();

  const issues = validateDraft(draft);
  const shown = showIssues ? issues : [];
  const busy = create.isPending || update.isPending || schedule.isPending;
  const [audience, setAudience] = React.useState<number | null>(null);

  const body = {
    name: draft.name.trim(),
    channel: draft.channel,
    segment: draft.segment,
    messages: Object.fromEntries(
      filledLanguages(draft.messages).map((l) => [l, (draft.messages[l] ?? "").trim()]),
    ),
    holdout_pct: draft.holdout_pct,
    attribution_days: draft.attribution_days,
  };

  /** Saves the draft (creating it the first time) and returns its id. */
  const save = async (): Promise<string | null> => {
    setError(undefined);
    setShowIssues(true);
    if (issues.length > 0) return null;
    try {
      if (loadedId.current) {
        await update.mutateAsync({ id: loadedId.current, body });
        return loadedId.current;
      }
      const created = await create.mutateAsync(body);
      loadedId.current = created.id;
      return created.id;
    } catch (err) {
      setError(problemMessage(err, t));
      return null;
    }
  };

  const onSaveDraft = async () => {
    const id = await save();
    if (!id) return;
    toast.success(t("campaigns.toast.created"));
    router.push(`/campaigns/new?id=${id}`);
  };

  const onSchedule = async () => {
    const id = await save();
    if (!id) return;
    try {
      await schedule.mutateAsync({
        id,
        sendAt: draft.send_at ? sendAtToIso(draft.send_at) : null,
      });
      toast.success(t("campaigns.toast.scheduled"));
      router.push(`/campaigns/${id}`);
    } catch (err) {
      setError(problemMessage(err, t));
    }
  };

  if (editId && existing.isLoading) return <Skeleton announce className="h-96 w-full" />;
  if (editId && existing.error)
    return <QueryError error={existing.error} onRetry={() => void existing.refetch()} />;

  const languages = filledLanguages(draft.messages);
  const previewText = draft.messages[previewLanguage] ?? "";

  return (
    <>
      <PageHeader
        title={t("campaigns.builder.title")}
        subtitle={t("campaigns.builder.subtitle")}
        back={{ href: "/campaigns", label: t("campaigns.builder.back") }}
      />

      <section className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
        <div className="grid gap-3 md:grid-cols-3">
          <TextField
            id="campaign-name"
            label={t("campaigns.builder.name")}
            placeholder={t("campaigns.builder.namePlaceholder")}
            value={draft.name}
            onChange={(name) => setDraft((d) => ({ ...d, name }))}
            error={
              issueFor(shown, "name")
                ? t(`campaigns.error.${issueFor(shown, "name")}` as `campaigns.error.nameTooShort`)
                : undefined
            }
          />
          <Choice
            id="campaign-channel"
            label={t("campaigns.builder.channel")}
            value={draft.channel}
            options={CAMPAIGN_CHANNELS.map((c) => ({
              value: c,
              label: t(`campaigns.channel.${c}`),
            }))}
            onChange={(channel) => setDraft((d) => ({ ...d, channel: channel as CampaignChannel }))}
          />
          <NumberField
            id="campaign-attribution"
            label={t("campaigns.builder.attribution")}
            value={draft.attribution_days}
            min={1}
            max={90}
            onChange={(v) => setDraft((d) => ({ ...d, attribution_days: v ?? 0 }))}
          />
        </div>
        <p className="text-small text-text-muted">{t("campaigns.builder.attributionHelp")}</p>
      </section>

      <section className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
        <h2 className="text-heading font-semibold">{t("campaigns.segment.title")}</h2>
        <SegmentBuilder
          value={draft.segment}
          onChange={(segment: CampaignSegment) => setDraft((d) => ({ ...d, segment }))}
          onCount={setAudience}
          error={issueFor(shown, "segment") ? t("campaigns.error.segmentEmpty") : undefined}
        />
      </section>

      <section className="grid gap-4 rounded-card border border-border bg-surface p-4 lg:grid-cols-[2fr_1fr]">
        <div className="flex min-w-0 flex-col gap-3">
          <h2 className="text-heading font-semibold">{t("campaigns.message.title")}</h2>
          <p className="text-small text-text-muted">{t("campaigns.message.defaultLanguage")}</p>
          {issueFor(shown, "messages") ? (
            <p className="text-small text-danger" role="alert" data-testid="message-error">
              {t(
                `campaigns.error.${issueFor(shown, "messages")}` as `campaigns.error.messageRequired`,
              )}
            </p>
          ) : null}
          {LOCALE_OPTIONS.map((l) => (
            <div key={l.locale} className="flex flex-col gap-1">
              <label
                htmlFor={`message-${l.locale}`}
                className="text-small font-semibold text-text-secondary"
              >
                {t("campaigns.message.forLanguage", { language: l.nativeName })}
              </label>
              <textarea
                id={`message-${l.locale}`}
                rows={2}
                maxLength={MESSAGE_MAX_CHARS}
                value={draft.messages[l.locale] ?? ""}
                onFocus={() => setPreviewLanguage(l.locale)}
                onChange={(e) =>
                  setDraft((d) => ({
                    ...d,
                    messages: { ...d.messages, [l.locale]: e.target.value },
                  }))
                }
                className="rounded-input border border-border bg-surface px-3 py-2 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary"
              />
            </div>
          ))}
        </div>
        <div className="flex flex-col gap-3">
          <Choice
            id="preview-language"
            label={t("campaigns.message.previewLanguage")}
            value={previewLanguage}
            options={LOCALE_OPTIONS.map((l) => ({ value: l.locale, label: l.nativeName }))}
            onChange={(v) => setPreviewLanguage((v || "en") as Locale)}
          />
          <PhonePreview
            channel={draft.channel}
            language={previewLanguage}
            text={previewText}
            tenantName={t("app.tenantFallback")}
          />
          <p className="text-small text-text-muted" data-testid="languages-filled">
            {languages.map((l) => l.toUpperCase()).join(" · ") || t("common.none")}
          </p>
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
        <h2 className="text-heading font-semibold">{t("campaigns.builder.schedule")}</h2>
        <div className="grid gap-3 md:grid-cols-3">
          <NumberField
            id="campaign-holdout"
            label={t("campaigns.builder.holdout")}
            value={draft.holdout_pct}
            min={0}
            max={50}
            onChange={(v) => setDraft((d) => ({ ...d, holdout_pct: v ?? 0 }))}
          />
          <div className="flex flex-col gap-1">
            <label
              htmlFor="campaign-send-at"
              className="text-small font-semibold text-text-secondary"
            >
              {t("campaigns.builder.sendAt")}
            </label>
            <input
              id="campaign-send-at"
              type="datetime-local"
              value={draft.send_at ?? ""}
              onChange={(e) => setDraft((d) => ({ ...d, send_at: e.target.value || null }))}
              className="h-10 rounded-input border border-border bg-surface px-3 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary"
            />
            <span className="text-small text-text-muted">{t("campaigns.builder.sendNow")}</span>
          </div>
          <div className="flex flex-col justify-end gap-1">
            <span className="text-small text-text-muted">{t("campaigns.builder.holdoutHelp")}</span>
          </div>
        </div>
        {audience !== null ? <ArmsSplit count={audience} holdout={draft.holdout_pct} /> : null}
        {issueFor(shown, "holdout_pct") || issueFor(shown, "send_at") ? (
          <p className="text-small text-danger" role="alert" data-testid="schedule-error">
            {t(
              `campaigns.error.${issueFor(shown, "holdout_pct") ?? issueFor(shown, "send_at")}` as `campaigns.error.holdoutRange`,
            )}
          </p>
        ) : null}
        <Note icon={<CalendarClock className="size-4" aria-hidden="true" />}>
          {t("campaigns.builder.scheduleHelp")}
        </Note>
      </section>

      {error ? (
        <p className="text-body text-danger" role="alert" data-testid="builder-error">
          {error}
        </p>
      ) : null}

      <div className="flex flex-wrap gap-2">
        <AppButton
          variant="secondary"
          loading={create.isPending || update.isPending}
          disabled={busy}
          onClick={() => void onSaveDraft()}
          data-testid="save-draft"
        >
          <Save className="size-4" aria-hidden="true" />
          {t("campaigns.builder.saveDraft")}
        </AppButton>
        <AppButton
          loading={schedule.isPending}
          disabled={busy}
          onClick={() => void onSchedule()}
          data-testid="schedule-campaign"
        >
          <CalendarClock className="size-4" aria-hidden="true" />
          {t("campaigns.builder.schedule")}
        </AppButton>
        <LinkButton href="/campaigns" variant="secondary">
          <ArrowLeft className="size-4" aria-hidden="true" />
          {t("campaigns.builder.back")}
        </LinkButton>
      </div>
    </>
  );
}

function ArmsSplit({ count, holdout }: { count: number; holdout: number }) {
  const t = useT();
  const arms = splitArms(count, holdout);
  return (
    <p className="tnum text-small text-text-secondary" data-testid="arms-split">
      {t("campaigns.arms.split", {
        target: formatNumber(arms.target),
        holdout: formatNumber(arms.holdout),
      })}
    </p>
  );
}
