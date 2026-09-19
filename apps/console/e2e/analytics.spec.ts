import { expect, test, type Page } from "@playwright/test";

/**
 * M4 analytics screens against the in-app mock API (lib/mock/analytics.ts): C10 owner home,
 * AN-011 filters in the URL, C20 -> C21 -> C22 day replay, C30 -> C31, C40 -> C41 P&L, and the
 * store manager's replay refusal (SPEC 2.6). Read-only mock, so tests run in parallel; each
 * signs in with its own number (the mock allows 3 OTP resends per number per 15 minutes).
 */
const STORE_MANAGER = "9000000004";

async function login(page: Page, phone: string) {
  await page.goto("/login");
  await page.getByLabel("Mobile number").fill(phone);
  await page.getByRole("button", { name: "Send OTP" }).click();
  await expect(page.getByTestId("login-otp-step")).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
  await page.waitForURL("**/home");
}

/** Most recent Monday before today (IST calendar): always a duty day in the mock. */
function lastMonday(): string {
  const d = new Date(Date.now() + 330 * 60_000);
  d.setUTCDate(d.getUTCDate() - 1);
  while (d.getUTCDay() !== 1) d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

test("C10 owner home loads every section from the mock", async ({ page }) => {
  await login(page, "9876510001");
  await expect(page.getByRole("heading", { level: 1, name: "Home" })).toBeVisible();
  const kpis = page.getByTestId("kpi-row");
  for (const key of [
    "revenue",
    "own_brand_share",
    "credit_outstanding",
    "credit_overdue",
    "verified_visits",
    "active_farmers",
    "open_flags",
  ])
    await expect(kpis.getByTestId(`kpi-${key}`)).toBeVisible();
  await expect(kpis.getByTestId("kpi-revenue")).toContainText("₹");
  await expect(kpis.getByTestId("kpi-revenue")).toContainText("Last year");
  await expect(page.getByTestId("revenue-trend").getByTestId("line-chart")).toHaveCount(2);
  await expect(page.getByTestId("own-brand-donut").getByTestId("share-donut")).toBeVisible();
  await expect(page.getByTestId("store-map")).toBeVisible();
  await expect(page.locator(".store-pin")).toHaveCount(24);
  await expect(page.getByTestId("credit-ageing").getByTestId("bar-chart")).toBeVisible();
  await expect(page.getByTestId("officers-top").getByTestId("officer-rank")).toHaveCount(5);
  await expect(page.getByTestId("officers-bottom").getByTestId("officer-rank")).toHaveCount(5);
  const flag = page.getByTestId("high-flags").getByTestId("high-flag").first();
  await expect(flag).toHaveAttribute("href", /^\/flags\/[0-9a-f-]+$/);
  await expect(page.getByTestId("crop-health").getByTestId("empty-state")).toBeVisible();
  // KPI definitions (SPEC 5.2) are tooltips.
  await kpis.getByTestId("kpi-verified_visits").getByTestId("info-tip").hover();
  await expect(kpis.getByTestId("kpi-verified_visits").getByRole("tooltip")).toHaveText(
    "A visit with a score of 70 or more.",
  );
});

test("AN-011: a filter change updates the URL and survives reload and back", async ({ page }) => {
  await login(page, "9876510002");
  const bar = page.getByTestId("filter-bar");
  await expect(page.locator(".store-pin")).toHaveCount(24);
  await bar.getByLabel("Cluster").selectOption({ label: "Telangana cluster (8 stores)" });
  await expect(page).toHaveURL(/[?&]cluster=cluster-tg(&|$)/);
  await expect(page.locator(".store-pin")).toHaveCount(8);
  await bar.getByLabel("Store").selectOption({ label: "FCC Warangal" });
  await expect(page).toHaveURL(/cluster=cluster-tg&store=store-wgl/);
  await bar.getByLabel("Crop").selectOption({ label: "Paddy" });
  await expect(page).toHaveURL(/store=store-wgl&crop=crop-paddy/);
  await expect(page.locator(".store-pin")).toHaveCount(1);

  await page.reload();
  await expect(bar.getByLabel("Store")).toHaveValue("store-wgl");
  await expect(bar.getByLabel("Crop")).toHaveValue("crop-paddy");
  await expect(page.locator(".store-pin")).toHaveCount(1);

  await page.goBack();
  await expect(page).not.toHaveURL(/crop=/);
  await expect(bar.getByLabel("Store")).toHaveValue("store-wgl");
  await expect(bar.getByLabel("Crop")).toHaveValue("");

  // A date range is written as from / to and kept when moving to another dashboard.
  await bar.getByLabel("Start date").fill("2026-06-01");
  await expect(page).toHaveURL(/from=2026-06-01/);
  await page.getByTestId("officers-top").getByTestId("officer-rank").first().click();
  await expect(page).toHaveURL(/\/field-team\/off-wgl-\d\?.*from=2026-06-01/);
});

test("C20 -> C21 -> C22: the replay shows the track, visits and gaps", async ({ page }) => {
  await login(page, "9876510003");
  await page.goto("/field-team");
  await expect(page.getByRole("heading", { level: 1, name: "Field team" })).toBeVisible();
  const table = page.getByTestId("data-table");
  await expect(table.getByTestId("sparkline").first()).toBeVisible();
  await expect(table.getByRole("row")).toHaveCount(31); // header + 30 officers
  // Sortable columns: sort by name ascending.
  await table.getByRole("button", { name: "Sort by Officer" }).click();
  await expect(table.getByRole("row").nth(1)).toContainText("Amol Thakre");

  await table.getByRole("link", { name: "Ravi Kumar" }).click();
  await expect(page).toHaveURL(/\/field-team\/off-wgl-1/);
  await expect(page.getByRole("heading", { level: 1, name: "Ravi Kumar" })).toBeVisible();
  await expect(page.getByTestId("officer-summary")).toContainText("Verified visits / day");
  await expect(page.getByTestId("recent-visits").getByRole("row").nth(1)).toBeVisible();

  const day = lastMonday();
  await page.getByTestId("replay-picker").getByLabel("Day to replay").fill(day);
  await page.getByRole("button", { name: "Open day replay" }).click();
  await expect(page).toHaveURL(new RegExp(`/field-team/off-wgl-1/replay\\?date=${day}`));
  await expect(page.getByTestId("replay-map")).toBeVisible();
  await expect(page.locator(".replay-track")).toHaveCount(3); // split at two gaps
  await expect(page.locator(".replay-visit")).toHaveCount(4);
  await expect(page.locator(".replay-visit-verified")).toHaveCount(2);
  await expect(page.locator(".replay-visit-partial")).toHaveCount(1);
  await expect(page.locator(".replay-visit-unverified")).toHaveCount(1);
  await expect(page.locator(".replay-gap")).toHaveCount(2);
  const gaps = page.getByTestId("replay-gaps");
  await expect(gaps.getByTestId("replay-gap-item")).toHaveCount(2);
  await expect(gaps).toContainText("No reason given");
  await expect(gaps).toContainText("Phone battery died");

  // Playback: moving the slider moves the clock and highlights the matching timeline item.
  const slider = page.getByTestId("replay-slider");
  const timeline = page.getByTestId("replay-timeline");
  await slider.fill("0");
  await expect(timeline.locator('[data-active="true"]')).toHaveAttribute("data-type", "duty_start");
  await expect(page.getByTestId("replay-clock")).toHaveText("08:30");
  await slider.fill("1000");
  await expect(timeline.locator('[data-active="true"]')).toHaveAttribute("data-type", "duty_end");
  // Jump to the first check-in from the timeline: visit details with the ProofChecklist.
  await timeline.getByTestId("timeline-item").filter({ hasText: "Checked in" }).first().click();
  const detail = page.getByTestId("visit-detail");
  await expect(detail.getByTestId("proof-checklist")).toBeVisible();
  await expect(detail.getByTestId("proof-checklist")).toContainText("Farmer confirmed");
  // Middle of the first gap (12:00 -> 13:30 IST): the marker waits and says so.
  await timeline.getByTestId("timeline-item").filter({ hasText: "Location gap" }).first().click();
  await slider.press("ArrowRight");
  await expect(page.getByTestId("in-gap")).toBeVisible();
});

test("C30 search -> C31 farmer 360 tabs", async ({ page }) => {
  await login(page, "9876510004");
  await page.goto("/farmers");
  await expect(page.getByRole("heading", { level: 1, name: "Farmers" })).toBeVisible();
  await expect(page.getByTestId("farmer-total")).toHaveText("72 farmers");
  await expect(page.getByTestId("load-more")).toBeVisible();
  await page.getByLabel("Search farmers").fill("Ramesh");
  await expect(page).toHaveURL(/[?&]q=Ramesh/);
  const rows = page.getByTestId("data-table").getByRole("row");
  await expect(rows.nth(1)).toContainText("Ramesh");
  await expect(page.getByTestId("farmer-total")).not.toHaveText("72 farmers");
  await page.getByLabel("Credit risk").selectOption({ label: "Low risk" });
  await expect(page).toHaveURL(/risk=low/);
  await page.getByLabel("Credit risk").selectOption({ label: "All" });
  await rows.nth(1).click();

  await expect(page).toHaveURL(/\/farmers\/farmer-\d{3}/);
  await expect(page.getByTestId("farmer-header")).toContainText("+91");
  await expect(page.getByTestId("consent-data")).toHaveText("Data consent given");
  await expect(page.getByTestId("tab-farms").getByTestId("farms-map")).toBeVisible();
  await expect(page.locator(".farm-polygon").first()).toBeVisible();
  for (const [tab, id] of [
    ["Visits", "tab-visits"],
    ["Orders", "tab-orders"],
    ["Khata", "tab-khata"],
    ["Consent", "tab-consent"],
    ["App usage", "tab-app"],
  ] as const) {
    await page.getByRole("tab", { name: new RegExp(`^${tab}`) }).click();
    await expect(page.getByTestId(id)).toBeVisible();
  }
  await expect(page).toHaveURL(/tab=app/);
  await page.reload();
  await expect(page.getByTestId("tab-app")).toBeVisible();
  await page.getByRole("tab", { name: /^Visits/ }).click();
  await expect(page.getByTestId("diagnoses").getByTestId("empty-state")).toBeVisible();
});

test("C40 -> C41 store detail shows the P&L by month", async ({ page }) => {
  await login(page, "9876510005");
  await page.goto("/stores");
  await expect(page.getByTestId("stores-chart").getByTestId("bar-chart")).toBeVisible();
  await page.getByTestId("data-table").getByRole("row").filter({ hasText: "FCC Warangal" }).click();
  await expect(page).toHaveURL(/\/stores\/store-wgl/);
  await expect(page.getByRole("heading", { level: 1, name: "FCC Warangal" })).toBeVisible();
  await expect(page.getByTestId("sales-by-category").getByTestId("bar-chart")).toBeVisible();
  await expect(page.getByTestId("brand-split").getByTestId("bar-chart")).toBeVisible();
  await expect(page.getByTestId("credit-ageing").getByTestId("bar-chart")).toBeVisible();
  await expect(page.getByTestId("stockouts")).toBeVisible();
  const pnl = page.getByTestId("pnl-table");
  await expect(pnl).toBeVisible();
  await expect(pnl.locator("thead th")).toHaveCount(13); // line + 12 months
  for (const line of [
    "Gross sales",
    "Discounts",
    "Net sales",
    "Cost of goods sold",
    "Gross margin",
    "Write-offs",
    "Contribution",
  ])
    await expect(pnl.getByRole("rowheader", { name: line, exact: true })).toBeVisible();
  await expect(page.getByTestId("pnl-note")).toContainText("Operating expenses");
});

test("a store manager never sees a location replay", async ({ page }) => {
  await login(page, STORE_MANAGER);
  await page.goto("/field-team");
  await expect(page.getByText("Distances and tracks are not shown for your role.")).toBeVisible();
  await expect(page.getByRole("button", { name: /Sort by Km/ })).toHaveCount(0);
  await page.goto("/field-team/off-wgl-1");
  await expect(page.getByRole("heading", { level: 1, name: "Ravi Kumar" })).toBeVisible();
  await expect(page.getByTestId("replay-picker")).toHaveCount(0);
  await expect(page.getByRole("link", { name: /Replay the day/ })).toHaveCount(0);
  await page.goto(`/field-team/off-wgl-1/replay?date=${lastMonday()}`);
  const refused = page.getByTestId("replay-forbidden");
  await expect(refused).toBeVisible();
  await expect(refused).toContainText("never shown to store managers");
  await expect(page.getByTestId("replay-map")).toHaveCount(0);
});
