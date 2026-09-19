"use client";

/**
 * C102 Settings (WC-012): every key of `GET /v1/settings` in a typed form grouped as visits and
 * geofence, duty and location, credit and money, languages, branding; values shown in metres,
 * minutes, rupees and IST clock times and converted back for `PATCH /v1/settings` (step-up,
 * SEC-028). After a save: "Saved and audited" with a link to the audit log filtered to settings
 * changes. The branding preview of both apps follows the form as it changes.
 */
import * as React from "react";
import Link from "next/link";
import { CheckCircle2, Plus, Trash2 } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { AppTextField } from "@/components/ds/AppTextField";
import { Skeleton } from "@/components/ds/Skeleton";
import { ApiError } from "@/lib/api";
import { LANGUAGES, SETTINGS_ROLES, type Language, type TenantSettings } from "@/lib/admin";
import { useSettings, useUpdateSettings } from "@/lib/hooks/admin";
import { LOCALE_OPTIONS } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import {
  DEFAULT_APP_NAMES,
  DEFAULT_PRIMARY_COLOUR,
  HEX_COLOUR,
  fieldForLoc,
  toForm,
  toPatch,
  validateSettingsForm,
  type SettingsErrors,
  type SettingsField,
  type SettingsFormValues,
} from "@/lib/settings-form";
import { AdminSubNav } from "./AdminSubNav";
import { BrandingPreview } from "./BrandingPreview";
import {
  CheckboxField,
  PageHeader,
  QueryError,
  RoleGate,
  SelectField,
  SessionGate,
} from "./common";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "./StepUp";

export const SETTINGS_AUDIT_HREF = "/admin/audit?entity=tenant&action=tenant_settings.update";

export function SettingsView() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C102">
      <PageHeader title={t("settings.title")} subtitle={t("settings.subtitle")} />
      <AdminSubNav />
      <SessionGate>
        <RoleGate roles={SETTINGS_ROLES}>
          <StepUpProvider>
            <SettingsContent />
          </StepUpProvider>
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function SettingsContent() {
  const q = useSettings();
  if (q.isLoading)
    return (
      <div className="flex flex-col gap-3">
        <Skeleton announce className="h-40 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  if (q.error || !q.data) return <QueryError error={q.error} onRetry={() => void q.refetch()} />;
  return <SettingsForm settings={q.data} />;
}

function Group({
  id,
  title,
  help,
  children,
}: {
  id: string;
  title: string;
  help?: string;
  children: React.ReactNode;
}) {
  return (
    <section
      aria-labelledby={id}
      className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4"
      data-testid={`settings-${id}`}
    >
      <div className="flex flex-col gap-1">
        <h2 id={id} className="text-heading font-semibold">
          {title}
        </h2>
        {help ? <p className="text-small text-text-secondary">{help}</p> : null}
      </div>
      <div className="grid gap-3 sm:grid-cols-2">{children}</div>
    </section>
  );
}

function SettingsForm({ settings }: { settings: TenantSettings }) {
  const t = useT();
  const stepUp = useStepUp();
  const save = useUpdateSettings(stepUp);
  const [values, setValues] = React.useState<SettingsFormValues>(() => toForm(settings));
  const [errors, setErrors] = React.useState<SettingsErrors>({});
  const [serverError, setServerError] = React.useState<string | undefined>();
  const [saved, setSaved] = React.useState(false);
  const [submitted, setSubmitted] = React.useState(false);

  const set = <K extends keyof SettingsFormValues>(key: K, value: SettingsFormValues[K]) => {
    setSaved(false);
    const next = { ...values, [key]: value };
    setValues(next);
    if (submitted) setErrors(validateSettingsForm(next));
  };

  const units = {
    m: t("settings.units.metres"),
    min: t("settings.units.minutes"),
    s: t("settings.units.seconds"),
    days: t("settings.units.days"),
  };

  const err = (field: SettingsField) => {
    const e = errors[field];
    if (!e) return undefined;
    const unit = e.params?.unit;
    const params =
      typeof unit === "string" && unit in units
        ? { ...e.params, unit: units[unit as keyof typeof units] }
        : e.params;
    return t(e.key, params);
  };

  const text = (
    field: Exclude<SettingsField, `gstin.${number}` | "languages_enabled" | "default_language">,
    label: string,
    extra: Partial<React.ComponentProps<typeof AppTextField>> = {},
  ) => (
    <AppTextField
      label={label}
      value={values[field]}
      onChange={(e) => set(field, e.target.value)}
      error={err(field)}
      name={field}
      {...extra}
    />
  );

  const patch = toPatch(values, settings);
  const dirty = Object.keys(patch).length > 0;

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitted(true);
    setServerError(undefined);
    const found = validateSettingsForm(values);
    setErrors(found);
    if (Object.keys(found).length) {
      setServerError(t("settings.fixErrors"));
      return;
    }
    if (!dirty) return;
    save.mutate(patch, {
      onSuccess: (next) => {
        setValues(toForm(next));
        setSaved(true);
        setSubmitted(false);
      },
      onError: (error) => {
        if (isStepUpCancelled(error)) return setServerError(t("stepUp.cancelled"));
        if (error instanceof ApiError && error.problem.errors?.length) {
          const mapped: SettingsErrors = {};
          for (const item of error.problem.errors) {
            const field = fieldForLoc(item.loc);
            if (field)
              mapped[field] = { key: "settings.errors.server", params: { msg: item.msg ?? "" } };
          }
          setErrors(mapped);
        }
        setServerError(problemMessage(error, t));
      },
    });
  };

  const toggleLanguage = (l: Language, on: boolean) =>
    set(
      "languages_enabled",
      LANGUAGES.filter((x) => (x === l ? on : values.languages_enabled.includes(x))),
    );

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_auto]">
      <form
        onSubmit={onSubmit}
        noValidate
        className="flex flex-col gap-4"
        data-testid="settings-form"
      >
        <Group
          id="visits"
          title={t("settings.groups.visits")}
          help={t("settings.groups.visitsHelp")}
        >
          {text("geofence_radius_m", t("settings.fields.geofence"), {
            suffix: units.m,
            inputMode: "numeric",
            helper: t("settings.help.range", { min: 10, max: 2000, unit: units.m }),
          })}
          {text("meeting_point_radius_m", t("settings.fields.meetingPoint"), {
            suffix: units.m,
            inputMode: "numeric",
            optional: true,
            helper: t("settings.help.meetingPoint"),
          })}
          {text("min_visit_minutes", t("settings.fields.minVisit"), {
            suffix: units.min,
            inputMode: "decimal",
            helper: t("settings.help.minVisit"),
          })}
          {text("consent_version", t("settings.fields.consentVersion"), { maxLength: 32 })}
        </Group>

        <Group id="duty" title={t("settings.groups.duty")} help={t("settings.groups.dutyHelp")}>
          {text("auto_duty_end_local_time", t("settings.fields.autoDutyEnd"), {
            type: "time",
            helper: t("settings.help.ist"),
          })}
          {text("idle_end_minutes", t("settings.fields.idleEnd"), {
            suffix: units.min,
            inputMode: "numeric",
            helper: t("settings.help.range", { min: 5, max: 720, unit: units.min }),
          })}
          {text("sampling_moving_s", t("settings.fields.samplingMoving"), {
            suffix: units.s,
            inputMode: "numeric",
            helper: t("settings.help.range", { min: 30, max: 3600, unit: units.s }),
          })}
          {text("sampling_stationary_s", t("settings.fields.samplingStationary"), {
            suffix: units.s,
            inputMode: "numeric",
            helper: t("settings.help.range", { min: 60, max: 7200, unit: units.s }),
          })}
          {text("sampling_upload_s", t("settings.fields.samplingUpload"), {
            suffix: units.s,
            inputMode: "numeric",
            helper: t("settings.help.range", { min: 60, max: 86400, unit: units.s }),
          })}
          {text("location_policy_version", t("settings.fields.locationPolicy"), { maxLength: 32 })}
        </Group>

        <Group id="money" title={t("settings.groups.money")} help={t("settings.groups.moneyHelp")}>
          {text("ta_rate_rupees", t("settings.fields.taRate"), {
            prefix: "₹",
            inputMode: "decimal",
            helper: t("settings.help.rupees", { max: "100" }),
          })}
          {text("credit_limit_rupees", t("settings.fields.creditLimit"), {
            prefix: "₹",
            inputMode: "decimal",
            helper: t("settings.help.rupees", { max: "10,00,00,000" }),
          })}
          {text("credit_due_days", t("settings.fields.creditDueDays"), {
            suffix: units.days,
            inputMode: "numeric",
            helper: t("settings.help.range", { min: 1, max: 730, unit: units.days }),
          })}
          {text("variance_rupees", t("settings.fields.variance"), {
            prefix: "₹",
            inputMode: "decimal",
            helper: t("settings.help.rupees", { max: "1,00,000" }),
          })}
          {text("webhook_replay_window_s", t("settings.fields.webhookWindow"), {
            suffix: units.s,
            inputMode: "numeric",
            helper: t("settings.help.range", { min: 30, max: 86400, unit: units.s }),
          })}
          {text("legal_name", t("settings.fields.legalName"), { optional: true, maxLength: 200 })}
          {text("invoice_prefix", t("settings.fields.invoicePrefix"), {
            optional: true,
            maxLength: 8,
            helper: t("settings.help.invoicePrefix"),
          })}
          <div className="flex flex-col gap-2 sm:col-span-2" data-testid="gstin-rows">
            <span className="text-small font-semibold text-text-secondary">
              {t("settings.fields.gstin")}
            </span>
            {values.gstin_by_state.map((row, i) => (
              <div key={i} className="flex flex-wrap items-start gap-2">
                <AppTextField
                  label={t("settings.fields.stateCode")}
                  value={row.state}
                  maxLength={2}
                  inputMode="numeric"
                  className="w-28"
                  onChange={(e) =>
                    set(
                      "gstin_by_state",
                      values.gstin_by_state.map((r, j) =>
                        j === i ? { ...r, state: e.target.value } : r,
                      ),
                    )
                  }
                />
                <AppTextField
                  label={t("settings.fields.gstinNumber")}
                  value={row.gstin}
                  maxLength={15}
                  className="min-w-56 flex-1"
                  error={err(`gstin.${i}`)}
                  onChange={(e) =>
                    set(
                      "gstin_by_state",
                      values.gstin_by_state.map((r, j) =>
                        j === i ? { ...r, gstin: e.target.value.toUpperCase() } : r,
                      ),
                    )
                  }
                />
                <AppButton
                  type="button"
                  variant="tertiary"
                  size="M"
                  className="mt-6"
                  aria-label={t("settings.removeGstin", { state: row.state || String(i + 1) })}
                  onClick={() =>
                    set(
                      "gstin_by_state",
                      values.gstin_by_state.filter((_, j) => j !== i),
                    )
                  }
                >
                  <Trash2 className="size-4" aria-hidden="true" />
                </AppButton>
              </div>
            ))}
            <AppButton
              type="button"
              variant="tertiary"
              size="M"
              className="self-start"
              onClick={() =>
                set("gstin_by_state", [...values.gstin_by_state, { state: "", gstin: "" }])
              }
            >
              <Plus className="size-4" aria-hidden="true" />
              {t("settings.addGstin")}
            </AppButton>
          </div>
        </Group>

        <Group
          id="languages"
          title={t("settings.groups.languages")}
          help={t("settings.groups.languagesHelp")}
        >
          <fieldset
            className="flex flex-col gap-2"
            aria-invalid={errors.languages_enabled ? true : undefined}
          >
            <legend className="mb-1 text-small font-semibold text-text-secondary">
              {t("settings.fields.languagesEnabled")}
            </legend>
            {LANGUAGES.map((l) => (
              <CheckboxField
                key={l}
                label={LOCALE_OPTIONS.find((o) => o.locale === l)?.nativeName ?? l}
                checked={values.languages_enabled.includes(l)}
                onChange={(e) => toggleLanguage(l, e.target.checked)}
              />
            ))}
            {err("languages_enabled") ? (
              <p role="alert" className="text-small text-danger">
                {err("languages_enabled")}
              </p>
            ) : null}
          </fieldset>
          <SelectField
            label={t("settings.fields.defaultLanguage")}
            value={values.default_language}
            onChange={(e) => set("default_language", e.target.value as Language)}
            options={LANGUAGES.map((l) => ({
              value: l,
              label: LOCALE_OPTIONS.find((o) => o.locale === l)?.nativeName ?? l,
            }))}
            error={err("default_language")}
          />
        </Group>

        <Group
          id="branding"
          title={t("settings.groups.branding")}
          help={t("settings.groups.brandingHelp")}
        >
          {text("app_name_agent", t("settings.fields.appNameAgent"), {
            optional: true,
            maxLength: 40,
            helper: t("settings.help.appNameDefault", { name: DEFAULT_APP_NAMES.agent }),
          })}
          {text("app_name_farmer", t("settings.fields.appNameFarmer"), {
            optional: true,
            maxLength: 40,
            helper: t("settings.help.appNameDefault", { name: DEFAULT_APP_NAMES.farmer }),
          })}
          <div className="flex items-end gap-2">
            <input
              type="color"
              aria-label={t("settings.fields.colourPicker")}
              value={
                HEX_COLOUR.test(values.primary_colour)
                  ? values.primary_colour
                  : DEFAULT_PRIMARY_COLOUR
              }
              onChange={(e) => set("primary_colour", e.target.value.toUpperCase())}
              className="mb-0.5 h-11 w-12 cursor-pointer rounded-input border border-border bg-surface"
            />
            {text("primary_colour", t("settings.fields.primaryColour"), {
              maxLength: 7,
              className: "flex-1",
              helper: t("settings.help.colour"),
            })}
          </div>
          {text("support_phone", t("settings.fields.supportPhone"), {
            optional: true,
            inputMode: "tel",
            maxLength: 16,
          })}
          {text("logo_blob_uri", t("settings.fields.logo"), {
            optional: true,
            maxLength: 512,
            helper: t("settings.help.logo"),
            className: "sm:col-span-2",
          })}
        </Group>

        <div className="sticky bottom-0 flex flex-wrap items-center justify-end gap-3 border-t border-border bg-background py-3">
          {saved ? (
            <p
              className="mr-auto flex items-center gap-2 text-body text-success"
              role="status"
              data-testid="settings-saved"
            >
              <CheckCircle2 className="size-5" aria-hidden="true" />
              {t("settings.savedAudited")}{" "}
              <Link href={SETTINGS_AUDIT_HREF} className="font-semibold text-primary underline">
                {t("settings.viewAudit")}
              </Link>
            </p>
          ) : serverError ? (
            <p role="alert" className="mr-auto text-small text-danger">
              {serverError}
            </p>
          ) : !dirty ? (
            <p className="mr-auto text-small text-text-muted">{t("settings.noChanges")}</p>
          ) : (
            <p className="mr-auto text-small text-text-secondary">
              {t("settings.pendingChanges", { n: Object.keys(patch).length })}
            </p>
          )}
          <AppButton
            type="button"
            variant="tertiary"
            disabled={!dirty || save.isPending}
            onClick={() => {
              setValues(toForm(settings));
              setErrors({});
              setServerError(undefined);
              setSubmitted(false);
            }}
          >
            {t("settings.discard")}
          </AppButton>
          <AppButton type="submit" loading={save.isPending} disabled={!dirty}>
            {t("settings.save")}
          </AppButton>
        </div>
      </form>

      <aside
        className="flex flex-col gap-3 xl:sticky xl:top-0 xl:self-start"
        aria-labelledby="preview-title"
      >
        <h2 id="preview-title" className="text-heading font-semibold">
          {t("settings.preview.title")}
        </h2>
        <p className="max-w-md text-small text-text-secondary">{t("settings.preview.help")}</p>
        <BrandingPreview
          agentName={values.app_name_agent}
          farmerName={values.app_name_farmer}
          colour={values.primary_colour}
          logoUri={values.logo_blob_uri}
          supportPhone={values.support_phone}
        />
      </aside>
    </div>
  );
}
