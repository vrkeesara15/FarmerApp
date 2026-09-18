import type { Metadata, Viewport } from "next";
import "./globals.css";
import { fontVariables } from "@/lib/fonts";
import { t } from "@/lib/i18n";
import { themeInitScript } from "@/components/theme/theme";
import { Providers } from "./providers";

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
    <html lang="en" className={fontVariables} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
      </head>
      <body className="min-h-screen antialiased">
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-50 focus:rounded-input focus:bg-surface focus:px-3 focus:py-2"
        >
          {t("app.skipToContent")}
        </a>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
