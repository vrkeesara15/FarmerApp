import * as React from "react";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { TopBar } from "@/components/ds/TopBar";
import { MOCK_STEP_UP_OTP, handleAdmin, resetMockAdmin } from "./mock/admin";
import { brandedPalette } from "./brand";
import { DEFAULT_BRAND, toConsoleBrand } from "./brand-context";
import type { Branding, PublicSettings } from "./admin";

/**
 * FA-008 acceptance in the console: "a second test tenant renders with its brand without a code
 * change".
 *
 * The brand is switched the way an owner switches it — `PATCH /v1/settings` through the settings
 * API mock — and read back from `GET /v1/settings/public`, which is the endpoint the shell (and
 * both apps) brand themselves from. The same `TopBar` is then rendered for each tenant with no
 * change to the component.
 */
const owner = { id: "u-owner", role: "owner" };

function call(method: string, path: string[], body: unknown = {}, headers = new Headers()) {
  const result = handleAdmin(method, path, new URLSearchParams(), body as never, owner, headers);
  if (!result) throw new Error(`mock has no route for ${method} ${path.join("/")}`);
  return result;
}

/** A step-up token, as the console's OTP dialog obtains one (SEC-028). */
function stepUpHeaders(): Headers {
  call("POST", ["auth", "step-up", "send"]);
  const verified = call("POST", ["auth", "step-up"], { code: MOCK_STEP_UP_OTP });
  const token = (verified.json as { step_up_token: string }).step_up_token;
  return new Headers({ "x-step-up-token": token });
}

function setBranding(branding: Partial<Branding>) {
  const result = call("PATCH", ["settings"], { branding }, stepUpHeaders());
  expect(result.status).toBe(200);
}

function publicBranding(): Branding {
  const result = call("GET", ["settings", "public"]);
  expect(result.status).toBe(200);
  return (result.json as PublicSettings).branding;
}

const TENANTS: Array<[string, Partial<Branding>, string, string]> = [
  [
    "tenant A (Harvest)",
    {
      app_name_agent: "Harvest Field",
      app_name_farmer: "Harvest Kisan",
      primary_colour: "#3B4BD8",
      logo_blob_uri: "https://cdn.example/harvest-logo.png",
      support_phone: "+919800000001",
    },
    "Harvest Field",
    "#3B4BD8",
  ],
  [
    "tenant B (Bhoomi)",
    {
      app_name_agent: "Bhoomi Officer",
      app_name_farmer: "Bhoomi",
      primary_colour: "#B4362A",
      logo_blob_uri: "https://cdn.example/bhoomi-logo.png",
      support_phone: "+919800000002",
    },
    "Bhoomi Officer",
    "#B4362A",
  ],
];

const noop = () => undefined;
const shell = (brand: ReturnType<typeof toConsoleBrand>) => (
  <TopBar
    tenantName={brand.name ?? "FarmerApp Console"}
    tenantLogoUrl={brand.logoUrl}
    supportPhone={brand.supportPhone}
    search=""
    onSearchChange={noop}
    dateRange={{ start: "2026-09-01", end: "2026-09-20" }}
    onDateRangeChange={noop}
    user={{ name: "Anita Rao", role: "Owner" }}
  />
);

describe("FA-008 console branding", () => {
  beforeEach(() => resetMockAdmin());

  for (const [name, branding, expectedName, expectedColour] of TENANTS) {
    it(`${name} reaches the shell through the settings API`, async () => {
      setBranding(branding);
      const brand = toConsoleBrand(publicBranding());
      expect(brand.name).toBe(expectedName);
      expect(brand.primaryColour).toBe(expectedColour);
      expect(brand.supportPhone).toBe(branding.support_phone);

      render(shell(brand));
      expect(screen.getByTestId("tenant-name")).toHaveTextContent(expectedName);
      expect(screen.getByTestId("brand-logo")).toHaveAttribute("src", branding.logo_blob_uri!);
    });
  }

  it("with no branding set the shipped console brand stands", () => {
    const brand = toConsoleBrand(publicBranding());
    expect(brand).toEqual(DEFAULT_BRAND);
    render(shell(brand));
    expect(screen.getByTestId("tenant-name")).toHaveTextContent("FarmerApp Console");
    expect(screen.getByTestId("brand-leaf")).toBeInTheDocument();
  });

  it("the derived tokens are what the apps will paint", () => {
    setBranding({ primary_colour: "#E0651B" });
    const brand = toConsoleBrand(publicBranding());
    // Orange is 3.0:1 on white; the console must show the corrected colour, not the swatch.
    expect(brandedPalette(brand.primaryColour, "light").primary).toBe("#B85514");
  });

  it("a half-typed colour never reaches the shell", () => {
    expect(toConsoleBrand({ ...DEFAULT_BRANDING, primary_colour: "#3B4" }).primaryColour).toBe(
      "#1F6B3A",
    );
  });
});

const DEFAULT_BRANDING: Branding = {
  app_name_agent: null,
  app_name_farmer: null,
  primary_colour: "#1F6B3A",
  logo_blob_uri: null,
  support_phone: null,
};
