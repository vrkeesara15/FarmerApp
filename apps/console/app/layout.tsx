import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import "./globals.css";
import { fontVariables } from "@/lib/fonts";
import { NONCE_HEADER } from "@/lib/security-headers";
import { DEFAULT_LOCALE, localeInitScript, t } from "@/lib/i18n";
import { themeInitScript } from "@/components/theme/theme";
import { SkipLink } from "@/components/ds/SkipLink";
import { Providers } from "./providers";

// Metadata is rendered on the server in the default language; page copy is localised on
// the client through useT() and switches live (FA-004).
export const metadata: Metadata = {
  title: { default: t("app.tenantFallback"), template: `%s · ${t("app.name")}` },
  description: t("login.subtitle"),
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
};

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  // SEC-022: the per-request CSP nonce minted by middleware.ts. The two bootstrap scripts below
  // are the console's only raw-HTML sinks (scripts/lint-dangerous-html.mjs keeps it that way);
  // their content is a constant from our own source and they must run before hydration.
  const nonce = (await headers()).get(NONCE_HEADER) ?? undefined;
  return (
    // lang is stamped by localeInitScript before hydration and by setLocale afterwards;
    // suppressHydrationWarning covers the server/client difference on this element only.
    <html lang={DEFAULT_LOCALE} className={fontVariables} suppressHydrationWarning>
      <head>
        <script nonce={nonce} dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        <script nonce={nonce} dangerouslySetInnerHTML={{ __html: localeInitScript }} />
      </head>
      <body className="min-h-screen antialiased">
        <SkipLink />
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
