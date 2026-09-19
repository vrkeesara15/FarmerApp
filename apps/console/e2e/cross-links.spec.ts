import { expect, test, type Page } from "@playwright/test";

/**
 * M4 merge: the analytics and inbox screens link to each other. C10 owner home lists the open
 * high-severity flags -> C71 flag detail -> its evidence record -> C31 farmer 360
 * (`RECORD_ROUTES` in lib/flags.ts). The home and inbox mocks share one flag list.
 */
async function login(page: Page, phone: string) {
  await page.route("https://tile.openstreetmap.org/**", (route) => route.abort());
  await page.goto("/login");
  await page.getByLabel("Mobile number").fill(phone);
  await page.getByRole("button", { name: "Send OTP" }).click();
  await expect(page.getByTestId("login-otp-step")).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
  await page.waitForURL("**/home");
}

test("owner home -> high-severity flag -> evidence record -> farmer 360", async ({ page }) => {
  await login(page, "9876510009");

  const flag = page
    .getByTestId("high-flags")
    .getByTestId("high-flag")
    .filter({ hasText: "Farm boundary overlaps a neighbour" });
  await expect(flag).toHaveAttribute("href", /^\/flags\/[0-9a-f-]+$/);
  await flag.click();
  await page.waitForURL(/\/flags\/[0-9a-f-]+$/);
  await expect(page.getByTestId("flag-rule")).toHaveText("VA-F03 v1");

  const record = page.getByTestId("evidence-records").getByRole("link", { name: "Yadagiri" });
  await expect(record).toHaveAttribute("href", "/farmers/farmer-010");
  await record.click();
  await page.waitForURL("**/farmers/farmer-010");
  await expect(page.getByTestId("farmer-header")).toContainText("+91");
  await expect(page.getByTestId("tab-farms").getByTestId("farms-map")).toBeVisible();
});

test("the TopBar date range is the dashboard's from / to URL filter", async ({ page }) => {
  await login(page, "9876510010");
  const top = page.getByTestId("top-bar");
  const bar = page.getByTestId("filter-bar");
  await top.getByLabel("Start date").fill("2026-06-01");
  await expect(page).toHaveURL(/[?&]from=2026-06-01(&|$)/);
  await expect(bar.getByLabel("Start date")).toHaveValue("2026-06-01");
  // The FilterBar writes the same params, and the TopBar follows.
  await bar.getByLabel("End date").fill("2026-06-30");
  await expect(page).toHaveURL(/[?&]to=2026-06-30(&|$)/);
  await expect(top.getByLabel("End date")).toHaveValue("2026-06-30");
  await page.reload();
  await expect(top.getByLabel("Start date")).toHaveValue("2026-06-01");
  await page.goBack();
  await expect(top.getByLabel("End date")).not.toHaveValue("2026-06-30");
});
