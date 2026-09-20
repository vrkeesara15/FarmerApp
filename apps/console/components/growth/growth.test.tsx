import * as React from "react";
import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { PreviewResult } from "./IncentivesView";
import { consentNote } from "@/lib/campaigns";
import { cronSummary } from "@/lib/exports";
import { t } from "@/lib/i18n";
import type { IncentiveOut } from "@/lib/incentives";

const preview = (over: Partial<IncentiveOut> = {}): IncentiveOut => ({
  officer_id: "off-1",
  officer_name: "Ramesh",
  period_start: "2026-08-01",
  period_end: "2026-09-01",
  status: "preview",
  rule_set_id: "rules-1",
  rule_version: 2,
  eligible: true,
  metrics: { verified_visits: 52, sales_paise: 40_000_00 },
  targets: { visits_verified: 45 },
  lines: [
    {
      component: "visits",
      metric: "verified_visits",
      value: 52,
      amount_paise: 24_000,
      capped: false,
      note: null,
    },
    {
      component: "sales",
      metric: "sales_paise",
      value: 40_000_00,
      amount_paise: 500_000,
      capped: true,
      note: null,
    },
  ],
  gross_paise: 524_000,
  clawback_paise: 800,
  amount_paise: 523_200,
  reasons: [],
  ...over,
});

describe("C90 payout preview rendering", () => {
  it("shows every component line with its value and amount", () => {
    render(<PreviewResult result={preview()} />);
    const lines = screen.getAllByTestId("preview-line");
    expect(lines).toHaveLength(2);
    expect(within(lines[0]!).getByText("visits")).toBeInTheDocument();
    expect(within(lines[0]!).getByText("52")).toBeInTheDocument();
    expect(lines[0]!.textContent).toContain("240");
  });

  it("marks a capped component and totals gross, clawback and payable", () => {
    render(<PreviewResult result={preview()} />);
    expect(screen.getAllByTestId("preview-line")[1]!.textContent).toContain(
      t("incentives.preview.capped"),
    );
    expect(screen.getByTestId("preview-total").textContent).toContain("5,232");
  });

  it("says when an officer is not eligible and why", () => {
    render(
      <PreviewResult
        result={preview({ eligible: false, amount_paise: 0, reasons: ["min_verified_visits"] })}
      />,
    );
    expect(screen.getByTestId("preview-eligible")).toHaveTextContent(
      t("incentives.preview.ineligible"),
    );
    expect(
      screen.getByText(t("incentives.preview.reason.min_verified_visits")),
    ).toBeInTheDocument();
  });

  it("marks a closed month as a frozen payout", () => {
    render(<PreviewResult result={preview({ status: "closed" })} />);
    expect(screen.getByText(t("incentives.preview.closed"))).toBeInTheDocument();
  });
});

describe("C81 consented-count copy (WC-008)", () => {
  const line = (count: number, excluded: number) => {
    const note = consentNote({ count, excluded_no_consent: excluded });
    return t(`campaigns.consent.${note.key}`, {
      count: note.params.count,
      excluded: note.params.excluded,
    });
  };

  it("always names the audience as farmers with marketing consent", () => {
    expect(line(120, 0)).toBe("120 farmers with marketing consent will receive this.");
  });

  it("says how many matching farmers consent excluded, and why", () => {
    const text = line(120, 31);
    expect(text).toContain("120 farmers with marketing consent");
    expect(text).toContain("31 matching farmers are left out");
    expect(text).toContain("withdrew it");
  });

  it("never reports a plain audience size when nothing consented", () => {
    expect(line(0, 8)).toBe(
      "No farmer with marketing consent matches. 8 matching farmers were left out for consent.",
    );
  });

  it("states that consent cannot be switched off and is re-checked at send time", () => {
    const always = t("campaigns.consent.always");
    expect(always).toContain("cannot be switched off");
    expect(always).toContain("send time");
  });
});

describe("C100 cron summary copy", () => {
  it("reads as a sentence in IST", () => {
    expect(cronSummary("0 8 * * 1", t)).toBe("Every Monday at 08:00 IST");
    expect(cronSummary("0 8 1 * *", t)).toContain("IST");
  });
});
