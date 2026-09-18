import {
  Noto_Sans,
  Noto_Sans_Devanagari,
  Noto_Sans_Kannada,
  Noto_Sans_Telugu,
} from "next/font/google";

/**
 * Noto Sans families per SPEC 13.1. Weights 400 and 600 only. Each exposes a CSS variable
 * consumed by the Tailwind fontFamily theme (with fallback stacks) — see tailwind.config.ts.
 */
export const notoSans = Noto_Sans({
  subsets: ["latin", "latin-ext"],
  weight: ["400", "600"],
  variable: "--font-latin",
  display: "swap",
  fallback: ["system-ui", "Segoe UI", "Roboto", "sans-serif"],
});

export const notoSansTelugu = Noto_Sans_Telugu({
  subsets: ["telugu"],
  weight: ["400", "600"],
  variable: "--font-telugu",
  display: "swap",
  fallback: ["Noto Sans", "system-ui", "sans-serif"],
});

export const notoSansKannada = Noto_Sans_Kannada({
  subsets: ["kannada"],
  weight: ["400", "600"],
  variable: "--font-kannada",
  display: "swap",
  fallback: ["Noto Sans", "system-ui", "sans-serif"],
});

export const notoSansDevanagari = Noto_Sans_Devanagari({
  subsets: ["devanagari"],
  weight: ["400", "600"],
  variable: "--font-devanagari",
  display: "swap",
  fallback: ["Noto Sans", "system-ui", "sans-serif"],
});

export const fontVariables = [
  notoSans.variable,
  notoSansTelugu.variable,
  notoSansKannada.variable,
  notoSansDevanagari.variable,
].join(" ");
