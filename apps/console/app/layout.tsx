import type { Metadata, Viewport } from "next";
import "./globals.css";
import { fontVariables } from "@/lib/fonts";
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

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    // lang is stamped by localeInitScript before hydration and by setLocale afterwards;
    // suppressHydrationWarning covers the server/client difference on this element only.
    <html lang={DEFAULT_LOCALE} className={fontVariables} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        <script dangerouslySetInnerHTML={{ __html: localeInitScript }} />
      </head>
      <body className="min-h-screen antialiased">
        <SkipLink />
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
