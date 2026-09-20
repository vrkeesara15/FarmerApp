import { describe, expect, it } from "vitest";
import {
  cronSummary,
  describeCron,
  formatBytes,
  isValidCron,
  parseRecipients,
  validateSchedule,
  DEFAULT_CRON,
} from "./exports";
import { t } from "./i18n";

describe("C100 cron parsing", () => {
  it("reads the API default (Monday 08:00 IST)", () => {
    expect(describeCron(DEFAULT_CRON)).toEqual({
      minute: 0,
      hour: 8,
      kind: "weekly",
      days: ["monday"],
      dayOfMonth: null,
      time: "08:00",
    });
  });

  it("reads daily, several week days, Sunday as 0 or 7, and monthly", () => {
    expect(describeCron("30 6 * * *")?.kind).toBe("daily");
    expect(describeCron("0 8 * * 1,3,5")?.days).toEqual(["monday", "wednesday", "friday"]);
    expect(describeCron("0 8 * * 7")?.days).toEqual(["sunday"]);
    expect(describeCron("0 8 * * 1-5")?.days).toEqual([
      "monday",
      "tuesday",
      "wednesday",
      "thursday",
      "friday",
    ]);
    expect(describeCron("0 8 1 * *")).toMatchObject({ kind: "monthly", dayOfMonth: 1 });
    expect(describeCron("0 8 * * 0-6")?.kind).toBe("daily");
  });

  it("refuses expressions it cannot describe", () => {
    expect(describeCron("0 8 * *")).toBeNull();
    expect(describeCron("*/15 * * * *")).toBeNull();
    expect(describeCron("0 25 * * 1")).toBeNull();
    expect(describeCron("0 8 * * 9")).toBeNull();
    expect(isValidCron("0 8 * * 1")).toBe(true);
    expect(isValidCron("nonsense")).toBe(false);
  });

  it("describes a month-restricted expression as custom", () => {
    expect(describeCron("0 8 * 6 1")?.kind).toBe("custom");
  });
});

describe("C100 cron summary text (always IST)", () => {
  it("names the day and the time", () => {
    expect(cronSummary("0 8 * * 1", t)).toBe("Every Monday at 08:00 IST");
    expect(cronSummary("15 18 * * 2,4", t)).toBe("Every Tuesday, Thursday at 18:15 IST");
    expect(cronSummary("0 7 * * *", t)).toBe("Every day at 07:00 IST");
    expect(cronSummary("0 8 1 * *", t)).toBe("On day 1 of every month at 08:00 IST");
  });

  it("shows an unreadable expression verbatim with the time zone", () => {
    expect(cronSummary("*/5 * * * *", t)).toBe("Cron */5 * * * * (IST)");
  });
});

describe("C100 schedule validation", () => {
  const base = {
    name: "Weekly orders",
    resource: "orders",
    recipients: ["a@example.com"],
    cron: DEFAULT_CRON,
  };

  it("accepts a complete schedule", () => {
    expect(validateSchedule(base)).toEqual([]);
  });

  it("reports the missing and invalid parts", () => {
    expect(
      validateSchedule({ name: "ab", resource: "", recipients: [], cron: "bad" }).map(
        (i) => i.code,
      ),
    ).toEqual(["nameTooShort", "resourceRequired", "recipientsRequired", "cronInvalid"]);
  });

  it("checks every recipient address", () => {
    expect(
      validateSchedule({ ...base, recipients: ["a@example.com", "nope"] }).map((i) => i.code),
    ).toEqual(["recipientInvalid"]);
  });

  it("splits recipients on commas, semicolons and newlines", () => {
    expect(parseRecipients("a@x.com, b@x.com\nc@x.com; ")).toEqual([
      "a@x.com",
      "b@x.com",
      "c@x.com",
    ]);
  });
});

describe("file sizes", () => {
  it("formats bytes, kilobytes and megabytes", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(2048)).toBe("2.0 KB");
    expect(formatBytes(3 * 1024 * 1024)).toBe("3.0 MB");
  });
});
