"use client";

/**
 * FA-008 in the console: the shell wears the brand of the tenant the signed-in user belongs to.
 *
 * The brand comes from `GET /v1/settings/public` — the same endpoint the two apps read, so the
 * console, the officer app and the farmer app cannot disagree about what a tenant looks like.
 * It is cached in localStorage per tenant, so a reload paints the tenant's colour on the first
 * frame instead of flashing the default green (the mobile apps do the same with their Drift
 * cache). Signed out, or with nothing cached, the shipped tokens stand.
 *
 * Only `color.primary.*` and the logo may be overridden (SPEC 13.1); `lib/brand.ts` derives the
 * four primary tokens from the tenant's one colour with a WCAG check.
 */
import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { adminApi, type Branding } from "./admin";
import { HEX, brandStyleSheet } from "./brand";
import { useSession } from "./session-context";

export interface ConsoleBrand {
  /** The tenant's display name, or null for the shipped one. */
  name: string | null;
  /** `#RRGGBB`, always valid. */
  primaryColour: string;
  /** The tenant's logo, or null for the leaf mark. */
  logoUrl: string | null;
  /** The tenant's support number in E.164, or null when it set none. */
  supportPhone: string | null;
}

export const DEFAULT_PRIMARY_COLOUR = "#1F6B3A";

export const DEFAULT_BRAND: ConsoleBrand = {
  name: null,
  primaryColour: DEFAULT_PRIMARY_COLOUR,
  logoUrl: null,
  supportPhone: null,
};

const blank = (v: string | null | undefined): string | null => {
  const s = (v ?? "").trim();
  return s === "" ? null : s;
};

/**
 * The console's name for a tenant is the officer app's name (`app_name_agent`): the brand row
 * carries one name per app and no separate console name, and the officer app is the surface
 * staff recognise. Documented in docs/branding.md.
 */
export function toConsoleBrand(branding: Branding | undefined): ConsoleBrand {
  if (!branding) return DEFAULT_BRAND;
  const colour = branding.primary_colour;
  return {
    name: blank(branding.app_name_agent) ?? blank(branding.app_name_farmer),
    primaryColour: HEX.test(colour ?? "") ? colour.toUpperCase() : DEFAULT_PRIMARY_COLOUR,
    logoUrl: blank(branding.logo_blob_uri),
    supportPhone: blank(branding.support_phone),
  };
}

const storageKey = (tenantId: string) => `farmerapp.console.brand.${tenantId}`;

function readCache(tenantId: string | undefined): ConsoleBrand | null {
  if (!tenantId) return null;
  try {
    const raw = window.localStorage.getItem(storageKey(tenantId));
    return raw ? (JSON.parse(raw) as ConsoleBrand) : null;
  } catch {
    return null;
  }
}

function writeCache(tenantId: string | undefined, brand: ConsoleBrand): void {
  if (!tenantId) return;
  try {
    window.localStorage.setItem(storageKey(tenantId), JSON.stringify(brand));
  } catch {
    /* private window, blocked site data: the brand still applies this session */
  }
}

const BrandContext = React.createContext<ConsoleBrand>(DEFAULT_BRAND);

export function BrandProvider({ children }: { children: React.ReactNode }) {
  const session = useSession();
  const tenantId = session.user?.tenant_id;
  const [cached, setCached] = React.useState<ConsoleBrand | null>(null);

  React.useEffect(() => setCached(readCache(tenantId)), [tenantId]);

  const query = useQuery({
    queryKey: ["brand", tenantId ?? "anonymous"],
    queryFn: () => adminApi.publicSettings(),
    enabled: session.status === "authenticated",
    staleTime: 5 * 60_000,
  });

  const brand = React.useMemo(
    () => (query.data ? toConsoleBrand(query.data.branding) : (cached ?? DEFAULT_BRAND)),
    [query.data, cached],
  );

  React.useEffect(() => {
    if (query.data) writeCache(tenantId, toConsoleBrand(query.data.branding));
  }, [query.data, tenantId]);

  return (
    <BrandContext.Provider value={brand}>
      {brand.primaryColour === DEFAULT_PRIMARY_COLOUR ? null : (
        // Injected after tokens.css, same specificity, so the later rule wins; both console
        // themes are repainted at once so the theme toggle needs no second pass.
        <style data-testid="brand-tokens">{brandStyleSheet(brand.primaryColour)}</style>
      )}
      {children}
    </BrandContext.Provider>
  );
}

/** The tenant's brand; outside a provider (tests, the design gallery) the shipped one. */
export function useBrand(): ConsoleBrand {
  return React.useContext(BrandContext);
}
