"use client";

/**
 * C102 live preview (WC-012): phone mockups of the field agent app and the farmer app home
 * screens rendered from the unsaved branding (app names, primary colour, logo, support phone).
 * Only the branding comes from the form; the rest of each screen is a static sketch.
 */
import type * as React from "react";
import { CalendarCheck, Camera, Leaf, MapPin, Phone, Play, Sprout } from "lucide-react";
import { DEFAULT_APP_NAMES, DEFAULT_PRIMARY_COLOUR, HEX_COLOUR } from "@/lib/settings-form";
import { useT } from "@/lib/i18n-client";

export interface BrandingPreviewProps {
  agentName: string;
  farmerName: string;
  colour: string;
  logoUri: string;
  supportPhone: string;
}

/** Readable text on the brand colour (WCAG relative luminance). */
export function onColour(hex: string): "#FFFFFF" | "#1A1A1A" {
  if (!HEX_COLOUR.test(hex)) return "#FFFFFF";
  const channel = (i: number) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  const l = 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
  return l > 0.4 ? "#1A1A1A" : "#FFFFFF";
}

const showableLogo = (uri: string) => /^(https:\/\/|data:image\/)/.test(uri.trim());

function Logo({ uri, name, fg, bg }: { uri: string; name: string; fg: string; bg: string }) {
  if (showableLogo(uri))
    return (
      // eslint-disable-next-line @next/next/no-img-element -- tenant-supplied preview image
      <img src={uri.trim()} alt="" className="size-8 rounded-full bg-white object-contain" />
    );
  return (
    <span
      aria-hidden="true"
      className="flex size-8 items-center justify-center rounded-full text-small font-semibold"
      style={{ background: fg, color: bg }}
    >
      {name.trim().charAt(0).toUpperCase() || <Leaf className="size-4" />}
    </span>
  );
}

function PhoneFrame({
  label,
  name,
  colour,
  logoUri,
  testId,
  children,
}: {
  label: string;
  name: string;
  colour: string;
  logoUri: string;
  testId: string;
  children: React.ReactNode;
}) {
  const bg = HEX_COLOUR.test(colour) ? colour : DEFAULT_PRIMARY_COLOUR;
  const fg = onColour(bg);
  return (
    <figure className="flex flex-col items-center gap-2" data-testid={testId}>
      <div className="w-56 overflow-hidden rounded-[2rem] border-8 border-text bg-background shadow-lg">
        <div
          className="flex items-center gap-2 px-3 pb-3 pt-5"
          style={{ background: bg, color: fg }}
          data-testid={`${testId}-header`}
          data-colour={bg.toUpperCase()}
        >
          <Logo uri={logoUri} name={name} fg={fg} bg={bg} />
          <span className="truncate text-body font-semibold" data-testid={`${testId}-name`}>
            {name}
          </span>
        </div>
        <div className="flex min-h-72 flex-col gap-2 p-3 text-small">{children}</div>
      </div>
      <figcaption className="text-small text-text-muted">{label}</figcaption>
    </figure>
  );
}

export function BrandingPreview({
  agentName,
  farmerName,
  colour,
  logoUri,
  supportPhone,
}: BrandingPreviewProps) {
  const t = useT();
  const bg = HEX_COLOUR.test(colour) ? colour : DEFAULT_PRIMARY_COLOUR;
  const fg = onColour(bg);
  const agent = agentName.trim() || DEFAULT_APP_NAMES.agent;
  const farmer = farmerName.trim() || DEFAULT_APP_NAMES.farmer;
  const card = "flex items-center gap-2 rounded-input border border-border bg-surface p-2";
  return (
    <div
      className="flex flex-wrap justify-center gap-6"
      aria-label={t("settings.preview.label")}
      role="group"
      data-testid="branding-preview"
    >
      <PhoneFrame
        label={t("settings.preview.agentApp")}
        name={agent}
        colour={bg}
        logoUri={logoUri}
        testId="preview-agent"
      >
        <p className="font-semibold text-text">{t("settings.preview.greeting")}</p>
        <button
          type="button"
          tabIndex={-1}
          className="flex items-center justify-center gap-2 rounded-input px-3 py-2 font-semibold"
          style={{ background: bg, color: fg }}
        >
          <Play className="size-4" aria-hidden="true" />
          {t("settings.preview.startDuty")}
        </button>
        <div className={card}>
          <CalendarCheck className="size-4" style={{ color: bg }} aria-hidden="true" />
          {t("settings.preview.todayVisits")}
        </div>
        <div className={card}>
          <MapPin className="size-4" style={{ color: bg }} aria-hidden="true" />
          {t("settings.preview.nearbyFarmers")}
        </div>
      </PhoneFrame>
      <PhoneFrame
        label={t("settings.preview.farmerApp")}
        name={farmer}
        colour={bg}
        logoUri={logoUri}
        testId="preview-farmer"
      >
        <p className="font-semibold text-text">{t("settings.preview.farmerGreeting")}</p>
        <button
          type="button"
          tabIndex={-1}
          className="flex items-center justify-center gap-2 rounded-input px-3 py-2 font-semibold"
          style={{ background: bg, color: fg }}
        >
          <Camera className="size-4" aria-hidden="true" />
          {t("settings.preview.scanCrop")}
        </button>
        <div className={card}>
          <Sprout className="size-4" style={{ color: bg }} aria-hidden="true" />
          {t("settings.preview.myFarms")}
        </div>
        <div className={card} data-testid="preview-support">
          <Phone className="size-4" style={{ color: bg }} aria-hidden="true" />
          {supportPhone.trim()
            ? t("settings.preview.support", { phone: supportPhone.trim() })
            : t("settings.preview.supportMissing")}
        </div>
      </PhoneFrame>
    </div>
  );
}
