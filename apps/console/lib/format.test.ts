import { describe, expect, it } from "vitest";
import {
  formatDateIst,
  formatDateTimeIst,
  formatDuration,
  formatInr,
  formatInrCompact,
  formatNumber,
  formatPercent,
  groupIndian,
  normaliseIndianMobile,
} from "./format";

describe("Indian grouping", () => {
  it("groups digits as 3 then 2s", () => {
    expect(groupIndian("125000")).toBe("1,25,000");
    expect(groupIndian("1234567")).toBe("12,34,567");
    expect(groupIndian("999")).toBe("999");
    expect(groupIndian("1000")).toBe("1,000");
    expect(groupIndian("100000000")).toBe("10,00,00,000");
  });

  it("formatNumber handles decimals and negatives", () => {
    expect(formatNumber(125000)).toBe("1,25,000");
    expect(formatNumber(-1234.5)).toBe("-1,234.50");
    expect(formatNumber(12.345, { decimals: 1 })).toBe("12.3");
    expect(formatNumber(Number.NaN)).toBe("—");
  });
});

describe("formatInr (paise)", () => {
  it("formats whole rupees without paise by default", () => {
    expect(formatInr(12500000)).toBe("₹1,25,000");
    expect(formatInr(0)).toBe("₹0");
  });
  it("shows paise when non-zero", () => {
    expect(formatInr(12500050)).toBe("₹1,25,000.50");
    expect(formatInr(5)).toBe("₹0.05");
  });
  it("respects paise mode", () => {
    expect(formatInr(12500000, { paise: "always" })).toBe("₹1,25,000.00");
    expect(formatInr(12500099, { paise: "never" })).toBe("₹1,25,001");
    expect(formatInr(12500000, { symbol: false })).toBe("1,25,000");
  });
  it("handles negatives and invalid", () => {
    expect(formatInr(-250000)).toBe("-₹2,500");
    expect(formatInr(Number.POSITIVE_INFINITY)).toBe("—");
  });
  it("compact", () => {
    expect(formatInrCompact(12500000)).toBe("₹1.25 L");
    expect(formatInrCompact(100000000000)).toBe("₹100 Cr");
    expect(formatInrCompact(250000)).toBe("₹2.5 K");
    expect(formatInrCompact(9900)).toBe("₹99");
  });
});

describe("dates in IST", () => {
  it("formats DD-MM-YYYY in IST regardless of source zone", () => {
    // 2026-03-31T20:30:00Z is 2026-04-01 02:00 IST
    expect(formatDateIst("2026-03-31T20:30:00Z")).toBe("01-04-2026");
    expect(formatDateTimeIst(new Date("2026-03-31T20:30:00Z"))).toBe("01-04-2026 02:00");
    expect(formatDateIst("not a date")).toBe("—");
  });
  it("formats durations and percentages", () => {
    expect(formatDuration(65)).toBe("1h 05m");
    expect(formatDuration(45)).toBe("45m");
    expect(formatPercent(0.4567)).toBe("45.7%");
  });
});

describe("normaliseIndianMobile", () => {
  it("accepts 10 digits or +91 prefix", () => {
    expect(normaliseIndianMobile("98765 43210")).toBe("9876543210");
    expect(normaliseIndianMobile("+91 98765-43210")).toBe("9876543210");
    expect(normaliseIndianMobile("12345")).toBeNull();
    expect(normaliseIndianMobile("1234567890")).toBeNull();
  });
});
