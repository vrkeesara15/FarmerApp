/**
 * Chart colours, all from design tokens (app/tokens.css, generated from design/tokens.json),
 * so they follow the Light / Dark theme without JavaScript. Categorical order is fixed and
 * never cycled: series 1 = Leaf (primary), 2 = info blue, 3 = warning amber — validated with
 * the dataviz palette check (light: all six checks pass; dark: CVD and contrast pass, the
 * token lightness sits slightly above the band, accepted as the approved dark theme).
 * Own brand always wears Turmeric (secondary), the tokens' own-brand highlight; comparison
 * series (last year, multi-brand) are the muted neutral. Status colours are reserved for
 * states (performance band, visit status, variance) and always carry a text label.
 */
export const CHART_SERIES = [
  "var(--color-primary)",
  "var(--color-info)",
  "var(--color-warning)",
] as const;

export const CHART = {
  grid: "var(--color-border)",
  axis: "var(--color-text-muted)",
  text: "var(--color-text)",
  surface: "var(--color-surface)",
  reference: "var(--color-text-muted)",
  ownBrand: "var(--color-secondary)",
  multiBrand: "var(--color-text-muted)",
  good: "var(--color-success)",
  warn: "var(--color-warning)",
  bad: "var(--color-danger)",
  none: "var(--color-text-muted)",
} as const;

export const BAND_COLOR: Record<string, string> = {
  green: CHART.good,
  amber: CHART.warn,
  red: CHART.bad,
  none: CHART.none,
};

export const VISIT_COLOR: Record<string, string> = {
  green: "var(--color-visit-verified)",
  amber: "var(--color-visit-partial)",
  red: "var(--color-visit-unverified)",
  grey: "var(--color-text-muted)",
};
