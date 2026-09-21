/**
 * FA-008 tenant branding for the console — and the one place the brand colour is turned into
 * tokens for every surface.
 *
 * The tenant supplies a single primary colour. Hover, container and on-primary are *derived*
 * with a WCAG contrast check, so a tenant cannot ship an unreadable console or an unreadable
 * app. The algorithm below is a line-for-line port of
 * `apps/mobile/packages/core/lib/src/theme/{contrast,brand}.dart`; `brand.test.ts` and
 * `packages/core/test/theme/brand_test.dart` assert the same hex values for the same input, so
 * the C102 live preview, the console shell and both apps cannot drift apart.
 *
 * Only `color.primary.*` may be overridden (SPEC 13.1); the neutrals, the status colours and the
 * type scale stay the shipped tokens.
 */

/** The theme a palette is derived for. Sunlight is mobile-only; the console has light + dark. */
export type BrandTheme = "light" | "sunlight" | "dark";

export interface BrandPalette {
  primary: string;
  primaryHover: string;
  primaryContainer: string;
  primaryOn: string;
}

interface Rgb {
  r: number;
  g: number;
  b: number;
}

/** Surface and background of each theme (design/tokens.json). */
const THEME_GROUND: Record<BrandTheme, { surface: string; background: string; container: string }> =
  {
    light: { surface: "#FFFFFF", background: "#FAF7F0", container: "#DCEFE2" },
    sunlight: { surface: "#FFFFFF", background: "#FFFFFF", container: "#FFFFFF" },
    dark: { surface: "#1E1C19", background: "#151412", container: "#1E3A2A" },
  };

/**
 * Minimum contrast the branded primary keeps against its theme's surface. Sunlight asks AAA
 * because it exists for a farmer in direct sun; the shipped tokens have the same relation.
 */
export const BRAND_MIN_CONTRAST: Record<BrandTheme, number> = {
  light: 4.5,
  sunlight: 7,
  dark: 4.5,
};

/** Contrast white / near-black on-primary must reach on the primary. */
export const ON_PRIMARY_MIN_CONTRAST = 4.5;
/** Near-black on-primary over a light brand colour (the Dark theme's primaryOn). */
export const BRAND_ON_PRIMARY_DARK = "#0B1A10";
/** One lightness step when a colour has to be pushed to pass AA. */
export const CONTRAST_STEP = 0.01;

export const HEX = /^#[0-9A-Fa-f]{6}$/;

function toRgb(hex: string): Rgb {
  return {
    r: parseInt(hex.slice(1, 3), 16) / 255,
    g: parseInt(hex.slice(3, 5), 16) / 255,
    b: parseInt(hex.slice(5, 7), 16) / 255,
  };
}

function toHex({ r, g, b }: Rgb): string {
  const part = (v: number) =>
    Math.min(255, Math.max(0, Math.round(v * 255)))
      .toString(16)
      .padStart(2, "0");
  return `#${part(r)}${part(g)}${part(b)}`.toUpperCase();
}

/** WCAG 2.2 relative luminance (0 = black, 1 = white). */
export function relativeLuminance(hex: string): number {
  const { r, g, b } = toRgb(hex);
  const channel = (v: number) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

/** WCAG 2.2 contrast ratio between two opaque colours (1..21, symmetric). */
export function contrastRatio(a: string, b: string): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** HSL lightness (0..1). */
export function lightnessOf(hex: string): number {
  const { r, g, b } = toRgb(hex);
  return (Math.max(r, g, b) + Math.min(r, g, b)) / 2;
}

/** [hex] with its HSL lightness replaced by [lightness]. */
export function withLightness(hex: string, lightness: number): string {
  const l = Math.min(1, Math.max(0, lightness));
  const { r, g, b } = toRgb(hex);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;
  const l0 = (max + min) / 2;
  if (delta === 0) return toHex({ r: l, g: l, b: l });
  const s = delta / (1 - Math.abs(2 * l0 - 1));
  let h: number;
  if (max === r) h = (((g - b) / delta) % 6 + 6) % 6;
  else if (max === g) h = (b - r) / delta + 2;
  else h = (r - g) / delta + 4;
  h *= 60;
  if (h < 0) h += 360;
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const x = chroma * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - chroma / 2;
  const sector = Math.floor(h / 60);
  const [rr, gg, bb] = (
    [
      [chroma, x, 0],
      [x, chroma, 0],
      [0, chroma, x],
      [0, x, chroma],
      [x, 0, chroma],
      [chroma, 0, x],
    ] as const
  )[Math.min(5, sector)] ?? [chroma, 0, x];
  return toHex({ r: rr + m, g: gg + m, b: bb + m });
}

/** Mixes [a] into [b]: `t === 0` is a, `t === 1` is b (sRGB, rounded). */
export function mixColours(a: string, b: string, t: number): string {
  const k = Math.min(1, Math.max(0, t));
  const ca = toRgb(a);
  const cb = toRgb(b);
  return toHex({
    r: ca.r + (cb.r - ca.r) * k,
    g: ca.g + (cb.g - ca.g) * k,
    b: ca.b + (cb.b - ca.b) * k,
  });
}

/** [colour] moved in 1 % lightness steps until it reaches [min] against [background]. */
export function ensureContrast(
  colour: string,
  background: string,
  min: number,
  darken: boolean,
): string {
  let out = colour;
  for (let i = 0; i < 101; i++) {
    if (contrastRatio(out, background) >= min) return out;
    const l = lightnessOf(out) + (darken ? -CONTRAST_STEP : CONTRAST_STEP);
    if (l < 0 || l > 1) return darken ? "#000000" : "#FFFFFF";
    out = withLightness(out, l);
  }
  return out;
}

/**
 * The four `color.primary.*` tokens derived from one brand colour, for one theme.
 *
 * 1. primary is darkened (lightened in Dark) until it reaches {@link BRAND_MIN_CONTRAST} against
 *    both the theme's surface and its background — it is used as icon and text colour.
 * 2. on-primary is white or {@link BRAND_ON_PRIMARY_DARK}, whichever contrasts more.
 * 3. hover is the primary 20 % darker (lighter in Dark), kept readable under on-primary.
 * 4. container is the primary mixed into the surface until the primary reads on it at 4.5:1;
 *    Sunlight has no tinted containers (SPEC 13.1) and keeps plain white.
 */
export function brandedPalette(primary: string, theme: BrandTheme): BrandPalette {
  const ground = THEME_GROUND[theme];
  const dark = theme === "dark";
  const darken = !dark;
  const min = BRAND_MIN_CONTRAST[theme];
  let p = ensureContrast(primary.toUpperCase(), ground.surface, min, darken);
  p = ensureContrast(p, ground.background, min, darken);
  const pick = (c: string) =>
    contrastRatio("#FFFFFF", c) >= contrastRatio(BRAND_ON_PRIMARY_DARK, c)
      ? "#FFFFFF"
      : BRAND_ON_PRIMARY_DARK;
  let on = pick(p);
  if (contrastRatio(on, p) < ON_PRIMARY_MIN_CONTRAST) {
    p = ensureContrast(p, on, ON_PRIMARY_MIN_CONTRAST, darken);
    on = pick(p);
  }
  const hover = ensureContrast(
    withLightness(p, lightnessOf(p) * (dark ? 1.2 : 0.8)),
    on,
    ON_PRIMARY_MIN_CONTRAST,
    !dark,
  );
  const container =
    theme === "sunlight"
      ? ground.container
      : ensureContrast(
          mixColours(p, dark ? ground.background : ground.surface, dark ? 0.8 : 0.88),
          p,
          ON_PRIMARY_MIN_CONTRAST,
          dark,
        );
  return { primary: p, primaryHover: hover, primaryContainer: container, primaryOn: on };
}

/**
 * The CSS the console injects after tokens.css to repaint `--color-primary*` in both console
 * themes at once. Same file order, same specificity, so the later rule wins — and the dark
 * palette is ready before the viewer flips the theme toggle.
 */
export function brandStyleSheet(primary: string): string {
  const vars = (p: BrandPalette) =>
    [
      `--color-primary: ${p.primary};`,
      `--color-primary-hover: ${p.primaryHover};`,
      `--color-primary-container: ${p.primaryContainer};`,
      `--color-primary-on: ${p.primaryOn};`,
    ].join(" ");
  return [
    `:root, [data-theme="light"] { ${vars(brandedPalette(primary, "light"))} }`,
    `[data-theme="dark"] { ${vars(brandedPalette(primary, "dark"))} }`,
  ].join("\n");
}
