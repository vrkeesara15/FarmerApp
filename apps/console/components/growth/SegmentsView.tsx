"use client";

/**
 * C32 farmer segments (AN-004): the WC-008 segment builder on its own screen, reached from the
 * C30 directory. The count is the consented reach (only farmers whose latest marketing consent
 * row is a grant); "Create a campaign" carries the segment into C81 through the URL.
 */
import * as React from "react";
import { useRouter } from "next/navigation";
import { Megaphone } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { PageHeader } from "@/components/analytics/Page";
import { RoleGate, SessionGate } from "@/components/admin/common";
import { CAMPAIGN_WRITE_ROLES, isEmptySegment, type CampaignSegment } from "@/lib/campaigns";
import { FARMER_ROLES } from "@/lib/nav";
import { useT } from "@/lib/i18n-client";
import { useSession } from "@/lib/session-context";
import { SegmentBuilder } from "./SegmentBuilder";

const STORAGE_KEY = "farmerapp.console.segment";

/** The draft segment C81 picks up (session storage, so nothing leaves the browser). */
export function readStoredSegment(): CampaignSegment | null {
  try {
    const raw = window.sessionStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as CampaignSegment) : null;
  } catch {
    return null;
  }
}

export function SegmentsView() {
  return (
    <div className="flex flex-col gap-4" data-screen="C32">
      <SessionGate>
        <RoleGate roles={FARMER_ROLES}>
          <Segments />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function Segments() {
  const t = useT();
  const router = useRouter();
  const { role } = useSession();
  const [segment, setSegment] = React.useState<CampaignSegment>({});
  const canCampaign = !!role && CAMPAIGN_WRITE_ROLES.includes(role);

  const openCampaign = () => {
    try {
      window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(segment));
    } catch {
      /* ignore: the builder simply starts empty */
    }
    router.push("/campaigns/new?from=segment");
  };

  return (
    <>
      <PageHeader
        title={t("segments.title")}
        subtitle={t("segments.subtitle")}
        back={{ href: "/farmers", label: t("segments.back") }}
      />
      <SegmentBuilder
        value={segment}
        onChange={setSegment}
        actions={
          canCampaign ? (
            <AppButton
              onClick={openCampaign}
              disabled={isEmptySegment(segment)}
              data-testid="segment-to-campaign"
            >
              <Megaphone className="size-4" aria-hidden="true" />
              {t("segments.createCampaign")}
            </AppButton>
          ) : null
        }
      />
    </>
  );
}
