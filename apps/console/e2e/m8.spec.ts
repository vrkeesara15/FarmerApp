import { expect, test, type Page } from "@playwright/test";

/**
 * M8 console screens against the in-app mock API (lib/mock/analytics.ts):
 *
 * * AN-016 the "Ask" panel on C10 owner home — an answer with rows, the expandable "SQL used"
 *   labelled as generated and read-only, and the friendly "I could not answer that";
 * * FM-013 the C95 referrals screen — per-store roll-up, the recent list with masked phone
 *   digits, and marking one rewarded.
 *
 * The referrals mock mutates (a reward sticks), so that block runs serially with its own
 * number; the Ask panel is read-only and runs in parallel.
 */
async function login(page: Page, phone: string) {
  await page.goto("/login");
  await page.getByLabel("Mobile number").fill(phone);
  await page.getByRole("button", { name: "Send OTP" }).click();
  await expect(page.getByTestId("login-otp-step")).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
  await page.waitForURL("**/home");
}

test("AN-016 the owner asks the spec's question and sees rows and the SQL", async ({ page }) => {
  await login(page, "9876520001");
  const panel = page.getByTestId("ask-panel");
  await expect(panel).toBeVisible();

  await panel.getByTestId("ask-input").fill("Which officers had fewer than 3 verified visits?");
  await panel.getByTestId("ask-submit").click();

  const answer = panel.getByTestId("ask-answer");
  await expect(answer).toBeVisible();
  await expect(answer).toContainText("verified visits");
  await expect(answer.getByTestId("data-table")).toBeVisible();

  // The SQL is shown, labelled as generated and read-only, behind a disclosure.
  const sql = panel.getByTestId("ask-sql");
  await expect(sql).toBeVisible();
  await expect(sql.getByText("SQL used")).toBeVisible();
  await sql.getByText("SQL used").click();
  await expect(sql.getByText(/read-only against authorised views/)).toBeVisible();
  await expect(sql.locator("pre")).toContainText("v_officer_week");
  await expect(sql.locator("pre")).toContainText("SELECT");
});

test("AN-016 a question it cannot answer gets a friendly reply, not an error", async ({
  page,
}) => {
  await login(page, "9876520002");
  const panel = page.getByTestId("ask-panel");
  await panel.getByTestId("ask-input").fill("What is the weather on Mars next year?");
  await panel.getByTestId("ask-submit").click();

  const refusal = panel.getByTestId("ask-could-not-answer");
  await expect(refusal).toBeVisible();
  await expect(refusal).toContainText("I could not answer that");
  await expect(panel.getByTestId("ask-answer")).toHaveCount(0);
  await expect(panel.getByTestId("ask-sql")).toHaveCount(0);
});

test("AN-016 a question carrying a phone number is refused before it is sent", async ({
  page,
}) => {
  await login(page, "9876520003");
  const panel = page.getByTestId("ask-panel");
  await panel.getByTestId("ask-input").fill("What did 9876543210 buy last month?");
  await panel.getByTestId("ask-submit").click();

  const refusal = panel.getByTestId("ask-could-not-answer");
  await expect(refusal).toBeVisible();
  await expect(refusal).toContainText("personal details");
});

test.describe("FM-013 referrals", () => {
  test.describe.configure({ mode: "serial" });

  test("C95 lists referrals per store and marks one rewarded", async ({ page }) => {
    await login(page, "9876520004");
    await page.getByRole("link", { name: "Referrals" }).click();
    await page.waitForURL("**/referrals");
    await expect(page.getByRole("heading", { level: 1, name: "Referrals" })).toBeVisible();

    const perStore = page.getByTestId("referrals-per-store");
    await expect(perStore.getByTestId("data-table")).toBeVisible();
    await expect(perStore.getByText("Attributed")).toBeVisible();

    const list = page.getByTestId("referrals-list");
    await expect(list.getByTestId("data-table")).toBeVisible();
    // SEC-026 / AN-014: four digits, never a number.
    await expect(list.getByText(/•••\s\d{4}/).first()).toBeVisible();

    const reward = list.getByRole("button", { name: "Mark rewarded" }).first();
    await expect(reward).toBeVisible();
    await reward.click();
    await expect(list.getByText("Rewarded").first()).toBeVisible();
  });
});
