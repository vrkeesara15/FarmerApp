import { expect, test, type Page } from "@playwright/test";

/**
 * M7 growth console against the in-app mock API (lib/mock/growth.ts, lib/mock/mlops.ts):
 * C80-C82 build a campaign -> schedule -> results, C90 edit an incentive rule -> preview payout,
 * C91 approve a travel claim, C100 run an export and see it listed, the AN-006 crop-health map
 * filter, C62 diagnosis quality from the API and the DX-012 model-release approval (step-up).
 * Serial: the steps share the mock state. OpenStreetMap tiles are blocked (offline run).
 */
test.describe.configure({ mode: "serial" });

/** One owner number per test: the mock allows three OTP sends per number per 15 minutes. */
const OWNERS = [
  "9876530001",
  "9876530002",
  "9876530003",
  "9876530004",
  "9876530005",
  "9876530006",
] as const;
const CLUSTER_HEAD = "9000000013";
const AGRONOMIST = "9000000018";
const CAMPAIGN_NAME = `Cotton advisory ${Date.now().toString(36)}`;
const SEGMENT_NAME = `Cotton kharif ${Date.now().toString(36)}`;

async function login(page: Page, phone: string) {
  await page.route("https://tile.openstreetmap.org/**", (route) => route.abort());
  await page.goto("/login");
  await page.getByLabel("Mobile number").fill(phone);
  await page.getByRole("button", { name: "Send OTP" }).click();
  await expect(page.getByTestId("login-otp-step")).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
  await page.waitForURL("**/home");
}

async function stepUp(page: Page) {
  const dialog = page.getByTestId("step-up-dialog");
  await expect(dialog).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await dialog.getByTestId(`otp-${i}`).fill(d);
  await expect(dialog).toBeHidden();
}

test("C81 -> C82: build a campaign on a consented segment, schedule it and read the results", async ({
  page,
}) => {
  await login(page, OWNERS[0]);
  await page.goto("/campaigns");
  await expect(page.getByRole("heading", { level: 1, name: "Campaigns" })).toBeVisible();
  await page.getByTestId("new-campaign").click();
  await expect(page.getByRole("heading", { level: 1, name: "New campaign" })).toBeVisible();

  // Empty segment: the builder refuses to guess an audience.
  await expect(page.getByTestId("consent-empty")).toBeVisible();

  await page.getByLabel("Campaign name").fill(CAMPAIGN_NAME);
  await page.getByTestId("segment-crops").getByRole("checkbox").first().check();

  // Only consented farmers are counted, and the copy says so.
  const consent = page.getByTestId("consent-line");
  await expect(consent).toBeVisible();
  await expect(consent).toContainText("farmers with marketing consent");
  await expect(page.getByTestId("consent-always")).toContainText("cannot be switched off");
  const count = Number((await consent.getAttribute("data-count")) ?? "0");
  expect(count).toBeGreaterThan(0);

  // The holdout split follows the consented count.
  await expect(page.getByTestId("arms-split")).toContainText("control group");

  // A message per language, with the phone preview.
  await page.getByLabel("English message").fill("Scout your cotton for pink bollworm this week.");
  await expect(page.getByTestId("preview-bubble")).toHaveText(
    "Scout your cotton for pink bollworm this week.",
  );
  await page.getByLabel("తెలుగు message").fill("ఈ వారం మీ పత్తిని పరిశీలించండి.");
  await expect(page.getByTestId("preview-bubble")).toHaveText("ఈ వారం మీ పత్తిని పరిశీలించండి.");
  await expect(page.getByTestId("languages-filled")).toContainText("EN");

  await page.getByTestId("schedule-campaign").click();
  await page.waitForURL(/\/campaigns\/camp-/);

  // C82: delivery, attribution and the lift against the holdout arm.
  await expect(page.getByRole("heading", { level: 1, name: CAMPAIGN_NAME })).toBeVisible();
  await expect(page.getByTestId("result-status")).toHaveText("Sent");
  await expect(page.getByTestId("roi-sent")).toBeVisible();
  await expect(page.getByTestId("roi-delivered")).toBeVisible();
  await expect(page.getByTestId("roi-failed")).toBeVisible();
  await expect(page.getByTestId("roi-orders")).toBeVisible();
  await expect(page.getByTestId("roi-revenue")).toBeVisible();
  await expect(page.getByTestId("roi-own-brand-lift")).toBeVisible();
  await expect(page.getByTestId("conversion-window")).toContainText("Conversion window");
  await expect(page.getByTestId("conversion-window")).toContainText("last touch");
  await expect(page.getByTestId("holdout-compare")).toBeVisible();

  // The list shows it as sent.
  await page.goto("/campaigns");
  await expect(page.getByRole("cell", { name: CAMPAIGN_NAME })).toBeVisible();
});

test("C90: edit an incentive rule and preview the payout", async ({ page }) => {
  await login(page, OWNERS[1]);
  await page.goto("/incentives");
  await expect(
    page.getByRole("heading", { level: 1, name: "Targets and incentives" }),
  ).toBeVisible();

  // VV-005 is stated up front.
  await expect(page.getByTestId("verified-visits-note")).toContainText("Verified visits only");

  await page.getByRole("tab", { name: "Incentive rules" }).click();
  await expect(page.getByTestId("rules-tab")).toBeVisible();
  await page.getByTestId("edit-rules").click();
  await expect(page.getByTestId("rule-editor")).toBeVisible();

  // Preview the active document first.
  await page.getByTestId("run-preview").click();
  const total = page.getByTestId("preview-total");
  await expect(total).toBeVisible();
  const before = await total.textContent();

  // Raise the per-unit rate of the first slab and preview the unsaved document.
  await page.getByLabel("Rate per unit (₹)").first().fill("400");
  await page.getByTestId("run-preview").click();
  await expect(total).not.toHaveText(before ?? "");
  await expect(page.getByTestId("preview-result")).toContainText("Payable");
});

test("C91: approve a travel claim against the computed km", async ({ page }) => {
  await login(page, CLUSTER_HEAD);
  await page.goto("/travel");
  await expect(
    page.getByRole("heading", { level: 1, name: "Travel allowance approvals" }),
  ).toBeVisible();
  await expect(page.getByTestId("km-help")).toContainText("duty tracks");
  await expect(page.getByTestId("computed-km").first()).toBeVisible();

  const approve = page.getByTestId(/^approve-claim-/).first();
  await approve.click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toContainText("Approve this claim?");
  await dialog.getByLabel("Note").fill("Km matches the duty track.");
  await dialog.getByRole("button", { name: "Approve" }).click();
  await expect(dialog).toBeHidden();

  await page.getByLabel("Status").selectOption("approved");
  await expect(page.getByTestId("claim-status").first()).toHaveText("Approved");
});

test("C100: run an export behind step-up and find it in the history", async ({ page }) => {
  await login(page, OWNERS[2]);
  await page.goto("/reports");
  await expect(page.getByRole("heading", { level: 1, name: "Reports and exports" })).toBeVisible();
  await expect(page.getByTestId("export-filters")).toBeVisible();

  await page.getByLabel("What to export").selectOption("orders");
  await page.getByTestId("run-export").click();
  await stepUp(page);

  await page.getByRole("tab", { name: "Past exports" }).click();
  await expect(page.getByTestId("history-tab")).toBeVisible();
  await expect(page.getByTestId("export-link").first()).toBeVisible();
  await expect(page.getByTestId("history-tab")).toContainText("signed");

  // A scheduled report shows its cron in IST, in words.
  await page.getByRole("tab", { name: "Scheduled reports" }).click();
  await expect(page.getByTestId("cron-summary").first()).toHaveText("Every Monday at 08:00 IST");
});

test("AN-006: the crop health map filters by crop and drills into a district", async ({ page }) => {
  await login(page, OWNERS[3]);
  await page.goto("/crop-health");
  await expect(page.getByRole("heading", { level: 1, name: "Crop health map" })).toBeVisible();
  await expect(page.getByTestId("crop-health-privacy")).toContainText("District level only");
  await expect(page.getByTestId("crop-health-map")).toBeVisible();

  // An outbreak is flagged and opens its district.
  await expect(page.getByTestId("outbreak-list")).toBeVisible();
  await page.getByTestId("outbreak-list").getByRole("button").first().click();
  await expect(page.getByTestId("crop-health-drill")).toContainText("week");

  // Filtering by crop narrows the cells and stays in the URL.
  await page.getByLabel("Crop").selectOption({ label: "Paddy" });
  await expect(page).toHaveURL(/crop=/);
  await expect(page.getByTestId("crop-health-map")).toBeVisible();
});

test("C62: diagnosis quality comes from the API, with the latest evaluation", async ({ page }) => {
  await login(page, AGRONOMIST);
  await page.goto("/agronomist/quality");
  await expect(page.getByRole("heading", { level: 1, name: "Diagnosis quality" })).toBeVisible();
  await expect(page.getByTestId("quality")).toBeVisible();
  await expect(page.getByTestId("quality-sources")).toBeVisible();
  await expect(page.getByTestId("quality-statuses")).toBeVisible();
  await expect(page.getByTestId("quality-review")).toContainText("Average");
  await expect(page.getByTestId("unknown-row").first()).toBeVisible();
  await expect(page.getByTestId("eval-top1")).toBeVisible();
  await expect(page.getByTestId("eval-crop-row").first()).toBeVisible();

  await page.getByLabel("Period").selectOption("7");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
});

test("DX-012: approving a model release needs step-up", async ({ page }) => {
  await login(page, AGRONOMIST);
  await page.goto("/agronomist/models");
  await expect(page.getByRole("heading", { level: 1, name: "Model releases" })).toBeVisible();
  await expect(page.getByTestId("current-model")).toContainText("2026.09.1");

  await page.getByTestId("approve-2026.09.2").click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toContainText("Approve 2026.09.2?");
  await dialog.getByLabel("Note").fill("Accuracy up across crops.");
  await dialog.getByRole("button", { name: "Approve" }).click();
  await stepUp(page);

  await expect(page.getByTestId("current-model")).toContainText("2026.09.2");
  await expect(page.getByTestId("release-status").first()).toHaveText("Approved");
});

test("AN-009: the data-quality tab reads the summary endpoint", async ({ page }) => {
  await login(page, OWNERS[4]);
  await page.goto("/flags");
  await page.getByRole("tab", { name: "Data quality" }).click();
  await expect(page.getByTestId("data-quality")).toBeVisible();
  await expect(page.getByTestId("data-quality-sample")).toContainText("flags");
  await expect(page.getByTestId("dq-resolution")).toBeVisible();
  await expect(page.getByTestId("dq-false-positive")).toBeVisible();
  await expect(page.getByTestId("dq-subjects")).toBeVisible();
  // Volume by rule now carries the median / p90 resolution time and the VA-006 precision.
  const volume = page.getByTestId("data-table").first();
  for (const header of ["Median resolution", "90th percentile", "Precision"])
    await expect(volume.getByRole("columnheader", { name: header })).toBeVisible();
  // The window is a server query, not a browser roll-up: changing it refetches.
  await page.getByLabel("Window").selectOption("30");
  await expect(page.getByTestId("data-quality-sample")).toContainText("flags");
});

test("C32: the segments builder previews, saves and hands a real segment to C81", async ({
  page,
}) => {
  await login(page, OWNERS[5]);
  await page.goto("/farmers");
  await page.getByTestId("open-segments").click();
  await expect(page.getByRole("heading", { level: 1, name: "Farmer segments" })).toBeVisible();
  // The saved segments of the tenant are listed before anything is built.
  await expect(page.getByTestId("saved-segments")).toContainText("Paddy growers");

  await page.getByTestId("segment-crops").getByRole("checkbox").first().check();
  await expect(page.getByTestId("consent-line")).toContainText("marketing consent");
  // AN-004 preview: counts and the breakdowns, as bars.
  const preview = page.getByTestId("segment-preview");
  await expect(preview).toBeVisible();
  await expect(preview.getByTestId("segment-preview-note")).toContainText("marketing consent");
  for (const id of ["segment-by-crop", "segment-by-acreage", "segment-by-spend"])
    await expect(preview.getByTestId(id).getByTestId("bar-chart")).toBeVisible();

  await page.getByTestId("segment-name").fill(SEGMENT_NAME);
  await page.getByTestId("segment-save").click();
  await expect(page.getByTestId("saved-segments")).toContainText(SEGMENT_NAME);

  // "Create a campaign" carries the saved segment's id, and C81 loads the definition.
  await page.getByTestId("segment-to-campaign").click();
  await page.waitForURL(/\/campaigns\/new\?segment=/);
  await expect(page.getByTestId("consent-line")).toBeVisible();
  await expect(page.getByTestId("segment-crops").getByRole("checkbox").first()).toBeChecked();
});

test("DX-011: C62 shows the nightly run, the alert state and accuracy per crop over time", async ({
  page,
}) => {
  await login(page, AGRONOMIST);
  await page.goto("/agronomist/quality");
  const panel = page.getByTestId("quality-accuracy");
  await expect(panel).toBeVisible();
  await expect(panel.getByTestId("eval-run")).toContainText("Status");
  await expect(panel.getByTestId("eval-top1")).toBeVisible();
  // No alert on the mock's latest run: the drop is under the tenant threshold.
  await expect(panel.getByTestId("eval-no-alert")).toContainText("5");
  await expect(panel.getByTestId("eval-crop-row").first()).toBeVisible();
  const trend = page.getByTestId("accuracy-trend");
  await expect(trend).toBeVisible();
  await expect(trend.getByTestId("line-chart")).toBeVisible();
});
