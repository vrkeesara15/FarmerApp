"use client";

/** C81 phone preview: the campaign message as the farmer sees it, per channel and language. */
import * as React from "react";
import { MessageSquare, Smartphone } from "lucide-react";
import { smsParts, type CampaignChannel } from "@/lib/campaigns";
import { useT } from "@/lib/i18n-client";
import { fontClassFor, type Locale } from "@/lib/i18n";
import { cn } from "@/lib/utils";

export function PhonePreview({
  channel,
  language,
  text,
  tenantName,
}: {
  channel: CampaignChannel;
  language: Locale;
  text: string;
  tenantName: string;
}) {
  const t = useT();
  const parts = smsParts(text);
  return (
    <div className="flex flex-col gap-2" data-testid="phone-preview">
      <h3 className="flex items-center gap-2 text-heading font-semibold">
        <Smartphone className="size-5 text-primary" aria-hidden="true" />
        {t("campaigns.message.preview")}
      </h3>
      <p className="text-small text-text-muted">{t("campaigns.message.previewHelp")}</p>
      <div className="mx-auto w-full max-w-[19rem] rounded-[2rem] border-4 border-text bg-background p-2 shadow-sm">
        <div className="mx-auto mb-2 h-1.5 w-16 rounded-pill bg-text" aria-hidden="true" />
        <div className="flex min-h-[18rem] flex-col gap-2 rounded-[1.25rem] bg-surface p-3">
          <div className="flex items-center gap-2 border-b border-border pb-2 text-small text-text-secondary">
            <MessageSquare className="size-4" aria-hidden="true" />
            <span className="truncate font-semibold">
              {channel === "sms"
                ? t("campaigns.channel.sms")
                : channel === "whatsapp"
                  ? t("campaigns.channel.whatsapp")
                  : t("campaigns.channel.push")}
            </span>
            <span className="ml-auto truncate">{tenantName}</span>
          </div>
          {text.trim() ? (
            <p
              lang={language}
              data-testid="preview-bubble"
              className={cn(
                "w-fit max-w-full whitespace-pre-wrap break-words rounded-card bg-primary-container px-3 py-2 text-body text-text",
                fontClassFor(language),
              )}
            >
              {text}
            </p>
          ) : (
            <p className="text-small text-text-muted">{t("campaigns.message.empty")}</p>
          )}
        </div>
      </div>
      <p className="tnum text-center text-small text-text-muted" data-testid="preview-parts">
        {t("campaigns.message.parts", { parts, chars: text.length })}
      </p>
    </div>
  );
}
