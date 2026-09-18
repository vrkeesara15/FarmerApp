import type { Config } from "tailwindcss";
import animate from "tailwindcss-animate";

/**
 * Tailwind theme maps 1:1 onto the CSS variables generated from design/tokens.json
 * (see scripts/tokens-to-css.mjs -> app/tokens.css). Never hard-code hex here.
 */
const config: Config = {
  darkMode: ["selector", '[data-theme="dark"]'],
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}", "./lib/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: "var(--color-primary)",
          hover: "var(--color-primary-hover)",
          container: "var(--color-primary-container)",
          on: "var(--color-primary-on)",
        },
        secondary: {
          DEFAULT: "var(--color-secondary)",
          container: "var(--color-secondary-container)",
          on: "var(--color-secondary-on)",
        },
        text: {
          DEFAULT: "var(--color-text)",
          secondary: "var(--color-text-secondary)",
          muted: "var(--color-text-muted)",
        },
        border: "var(--color-border)",
        surface: "var(--color-surface)",
        background: "var(--color-background)",
        success: { DEFAULT: "var(--color-success)", container: "var(--color-success-container)" },
        warning: { DEFAULT: "var(--color-warning)", container: "var(--color-warning-container)" },
        danger: { DEFAULT: "var(--color-danger)", container: "var(--color-danger-container)" },
        info: { DEFAULT: "var(--color-info)", container: "var(--color-info-container)" },
        confidence: {
          high: "var(--color-confidence-high)",
          medium: "var(--color-confidence-medium)",
          low: "var(--color-confidence-low)",
        },
        visit: {
          verified: "var(--color-visit-verified)",
          partial: "var(--color-visit-partial)",
          unverified: "var(--color-visit-unverified)",
        },
      },
      fontFamily: {
        sans: ["var(--font-latin)", "system-ui", "sans-serif"],
        telugu: ["var(--font-telugu)", "var(--font-latin)", "sans-serif"],
        kannada: ["var(--font-kannada)", "var(--font-latin)", "sans-serif"],
        devanagari: ["var(--font-devanagari)", "var(--font-latin)", "sans-serif"],
      },
      fontSize: {
        display: [
          "var(--text-display-size)",
          { lineHeight: "var(--text-display-line)", fontWeight: "var(--text-display-weight)" },
        ],
        title: [
          "var(--text-title-size)",
          { lineHeight: "var(--text-title-line)", fontWeight: "var(--text-title-weight)" },
        ],
        heading: [
          "var(--text-heading-size)",
          { lineHeight: "var(--text-heading-line)", fontWeight: "var(--text-heading-weight)" },
        ],
        body: [
          "var(--text-body-size)",
          { lineHeight: "var(--text-body-line)", fontWeight: "var(--text-body-weight)" },
        ],
        small: [
          "var(--text-small-size)",
          { lineHeight: "var(--text-small-line)", fontWeight: "var(--text-small-weight)" },
        ],
      },
      fontWeight: {
        regular: "var(--font-weight-regular)",
        semibold: "var(--font-weight-semibold)",
      },
      spacing: {
        "1": "var(--space-1)",
        "2": "var(--space-2)",
        "3": "var(--space-3)",
        "4": "var(--space-4)",
        "6": "var(--space-6)",
        "8": "var(--space-8)",
        "12": "var(--space-12)",
        screen: "var(--space-screen-padding)",
      },
      borderRadius: {
        input: "var(--radius-input)",
        chip: "var(--radius-chip)",
        card: "var(--radius-card)",
        sheet: "var(--radius-sheet)",
        pill: "var(--radius-pill)",
      },
      borderWidth: { DEFAULT: "var(--border-width)" },
      boxShadow: {
        flat: "var(--elevation-flat)",
        sheet: "var(--elevation-sheet)",
      },
      height: {
        touch: "var(--size-touch-target-min)",
        "btn-l": "var(--size-primary-button-height)",
      },
      minHeight: { touch: "var(--size-touch-target-min)" },
      minWidth: { touch: "var(--size-touch-target-min)" },
      width: { icon: "var(--size-icon)" },
    },
  },
  plugins: [animate],
};

export default config;
