import { describe, expect, it } from "vitest";
import {
  BRAND_MIN_CONTRAST,
  ON_PRIMARY_MIN_CONTRAST,
  brandStyleSheet,
  brandedPalette,
  contrastRatio,
  type BrandTheme,
} from "./brand";

/**
 * FA-008 / NF-009. Two things are checked here:
 *
 * 1. Whatever a tenant picks, the derived tokens pass WCAG AA in every theme — including two
 *    colours chosen to be hostile (a yellow no white can sit on, a near-black).
 * 2. The derivation agrees hex for hex with the Flutter one
 *    (`apps/mobile/packages/core/test/theme/brand_test.dart`), which is what makes the C102
 *    live preview an honest preview of what the officer and the farmer will see.
 */
const THEMES: BrandTheme[] = ["light", "sunlight", "dark"];

const GROUND: Record<BrandTheme, { surface: string; background: string }> = {
  light: { surface: "#FFFFFF", background: "#FAF7F0" },
  sunlight: { surface: "#FFFFFF", background: "#FFFFFF" },
  dark: { surface: "#1E1C19", background: "#151412" },
};

const BRANDS = {
  "fresh crops indigo": "#3B4BD8",
  "sun agro orange": "#E0651B",
  "bright yellow (hostile)": "#FFE600",
  "near black": "#050505",
  "saturated red": "#FF0000",
  "default leaf": "#1F6B3A",
};

describe("brandedPalette", () => {
  for (const [name, colour] of Object.entries(BRANDS)) {
    for (const theme of THEMES) {
      it(`${name} keeps WCAG AA in ${theme}`, () => {
        const p = brandedPalette(colour, theme);
        expect(contrastRatio(p.primary, GROUND[theme].surface)).toBeGreaterThanOrEqual(
          BRAND_MIN_CONTRAST[theme],
        );
        expect(contrastRatio(p.primary, GROUND[theme].background)).toBeGreaterThanOrEqual(4.5);
        expect(contrastRatio(p.primaryOn, p.primary)).toBeGreaterThanOrEqual(
          ON_PRIMARY_MIN_CONTRAST,
        );
        expect(contrastRatio(p.primaryOn, p.primaryHover)).toBeGreaterThanOrEqual(
          ON_PRIMARY_MIN_CONTRAST,
        );
        expect(contrastRatio(p.primary, p.primaryContainer)).toBeGreaterThanOrEqual(4.5);
      });
    }
  }

  it("sunlight keeps plain white containers (SPEC 13.1: no tints)", () => {
    expect(brandedPalette("#3B4BD8", "sunlight").primaryContainer).toBe("#FFFFFF");
  });

  it("matches the Flutter derivation hex for hex", () => {
    // The same expectations as packages/core/test/theme/brand_test.dart.
    expect(brandedPalette("#3B4BD8", "light")).toEqual({
      primary: "#3B4BD8",
      primaryHover: "#2533B7",
      primaryContainer: "#E7E9FA",
      primaryOn: "#FFFFFF",
    });
    expect(brandedPalette("#3B4BD8", "sunlight").primary).toBe("#3343D6");
    expect(brandedPalette("#3B4BD8", "dark")).toEqual({
      primary: "#6B7BE4",
      primaryHover: "#A4AEEE",
      primaryContainer: "#181B27",
      primaryOn: "#0B1A10",
    });
    // A colour the check has to move: orange is 3.0:1 on white and is darkened until it reads.
    expect(brandedPalette("#E0651B", "light").primary).toBe("#B85514");
    expect(brandedPalette("#E0651B", "sunlight").primary).toBe("#8B430F");
    // The shipped leaf derives to itself in Light (it already passes).
    expect(brandedPalette("#1F6B3A", "light").primary).toBe("#1F6B3A");
  });
});

describe("brandStyleSheet", () => {
  it("repaints both console themes and nothing else", () => {
    const css = brandStyleSheet("#B4362A");
    expect(css).toContain(':root, [data-theme="light"]');
    expect(css).toContain('[data-theme="dark"]');
    expect(css).toContain(`--color-primary: ${brandedPalette("#B4362A", "light").primary};`);
    expect(css).toContain(`--color-primary: ${brandedPalette("#B4362A", "dark").primary};`);
    // Neutrals, status colours and type are not a tenant's to change (SPEC 13.1).
    expect(css).not.toContain("--color-text");
    expect(css).not.toContain("--color-danger");
  });
});
