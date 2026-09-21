import { expect, test, type Page } from "@playwright/test";

/**
 * NF-013 C104 data-principal requests against the in-app mock API (lib/mock/admin.ts):
 * the queue and its filters, the received -> in progress -> completed path, applying a
 * correction behind step-up (SEC-028) and the erasure report that shows which classes the law
 * makes us keep. Serial: the steps share the mock's queue state.
 */
test.describe.configure({ mode: "serial" });

const OWNER = "9876510020";
const TENANT_ADMIN = "9000000019";
const AUDITOR = "9000000015";

async function login(page: Page, phone: string) {
  await page.goto("/login");
  await page.getByLabel("Mobile number").fill(phone);
  await page.getByRole("button", { name: "Send OTP" }).click();
  await expect(page.getByTestId("login-otp-step")).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
  await page.waitForURL(/\/(home|field-team|flags|products)/);
}

async function stepUp(page: Page) {
  const dialog = page.getByTestId("step-up-dialog");
  await expect(dialog).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await dialog.getByTestId(`otp-${i}`).fill(d);
  await expect(dialog).toBeHidden();
}

async function openQueue(page: Page, phone: string) {
  await login(page, phone);
  await page.goto("/admin/data-requests");
  await expect(page.getByRole("heading", { level: 1, name: "Data requests" })).toBeVisible();
}

/** Select a request by the text of its row and return its detail panel. */
async function select(page: Page, rowText: string) {
  await page.getByRole("row").filter({ hasText: rowText }).getByRole("button").first().click();
  const detail = page.getByTestId("request-detail");
  await expect(detail).toBeVisible();
  return detail;
}

test("C104: the queue lists every request, oldest deadline first, and filters", async ({
  page,
}) => {
  await openQueue(page, OWNER);

  const rows = page.getByTestId("data-table").locator("tbody tr");
  // The deletion request is past its statutory deadline, so it leads the queue with a badge.
  await expect(rows.first()).toContainText("Erasure");
  expect(await rows.count()).toBeGreaterThanOrEqual(6);
  await expect(rows.first().getByTestId("request-overdue")).toBeVisible();
  // Handled requests sink below the open ones.
  await expect(rows.last().getByTestId("request-status")).toHaveText(/Completed|Rejected/);

  await page.getByTestId("filter-type").selectOption("correction");
  await expect(rows).toHaveCount(1);
  await expect(rows.first().getByTestId("request-type")).toHaveText("Correction");

  await page.getByTestId("filter-type").selectOption("");
  await page.getByTestId("filter-status").selectOption("received");
  for (const text of await rows.getByTestId("request-status").allTextContents())
    expect(text).toBe("Received");

  await page.getByTestId("filter-status").selectOption("rejected");
  await expect(rows).toHaveCount(1);
  await expect(page.getByTestId("data-table")).toContainText("Price complaint");
});

test("C104: Start then Complete moves a grievance through the queue", async ({ page }) => {
  await openQueue(page, TENANT_ADMIN);
  const detail = await select(page, "Campaign messages after withdrawing consent");
  await expect(detail.getByTestId("request-status")).toHaveText("Received");

  await detail.getByRole("button", { name: "Start", exact: true }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Start", exact: true }).click();
  await expect(page.getByTestId("request-detail").getByTestId("request-status")).toHaveText(
    "In progress",
  );
  // No step-up for a status move: only the destructive calls need a fresh code.
  await expect(page.getByTestId("step-up-dialog")).toHaveCount(0);

  await page.getByTestId("request-detail").getByRole("button", { name: "Complete" }).click();
  const dialog = page.getByRole("dialog");
  await dialog.getByRole("button", { name: "Complete" }).click();
  await expect(dialog.getByText("Add a note that explains the decision.")).toBeVisible();
  await dialog
    .getByTestId("resolution-note")
    .fill("Consent withdrawal honoured; the farmer was removed from every sender list.");
  await dialog.getByRole("button", { name: "Complete" }).click();
  await expect(dialog).toBeHidden();

  const done = page.getByTestId("request-detail");
  await expect(done.getByTestId("request-status")).toHaveText("Completed");
  await expect(done.getByTestId("detail-resolution")).toContainText("Consent withdrawal honoured");
  // A closed request offers no further action.
  await expect(done.getByTestId("request-actions").getByRole("button")).toHaveCount(0);
});

test("C104: applying a correction shows the field diff and needs step-up", async ({ page }) => {
  await openQueue(page, OWNER);
  const detail = await select(page, "village and the spelling");
  await expect(detail.getByTestId("request-status")).toHaveText("In progress");
  // The requested changes are visible before anything is applied.
  await expect(detail.getByTestId("correction-row")).toHaveCount(3);

  await detail.getByRole("button", { name: "Apply correction" }).click();
  const dialog = page.getByRole("dialog");
  const diff = dialog.getByTestId("correction-diff");
  await expect(diff.getByTestId("correction-row")).toHaveCount(3);
  await expect(diff).toContainText("village");
  await expect(diff).toContainText("Kothapally");
  await expect(diff).toContainText("Imran Shaikh");
  await expect(diff).toContainText("You will be asked for a one-time code.");

  await dialog.getByRole("button", { name: "Apply correction" }).click();
  await stepUp(page);
  await expect(dialog).toBeHidden();
  await expect(page.getByText("3 field(s) corrected")).toBeVisible();

  const applied = page.getByTestId("correction-applied");
  await expect(applied.getByTestId("correction-row")).toHaveCount(3);
  await expect(page.getByTestId("request-detail").getByTestId("request-status")).toHaveText(
    "Completed",
  );
});

test("C104: running an erasure reports what was kept and why", async ({ page }) => {
  await openQueue(page, OWNER);
  const detail = await select(page, "delete his account");
  await expect(detail.getByTestId("request-overdue")).toBeVisible();

  await detail.getByRole("button", { name: "Run erasure" }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog.getByTestId("erasure-step-up-note")).toBeVisible();
  await dialog.getByRole("button", { name: "Run erasure" }).click();
  await stepUp(page);
  await expect(dialog).toBeHidden();

  const report = page.getByTestId("erasure-report");
  await expect(report).toBeVisible();
  await expect(report.getByTestId("erased-classes")).toContainText("farmer_profile");
  const financial = report.locator(
    '[data-testid="retained-class"][data-class="financial_records"]',
  );
  await expect(financial).toContainText("8 financial years");
  await expect(financial).toContainText("Kept until");
  await expect(page.getByTestId("request-detail").getByTestId("request-status")).toHaveText(
    "Completed",
  );
});

test("C104: an access request hands over the export as JSON", async ({ page }) => {
  await openQueue(page, OWNER);
  const detail = await select(page, "copy of everything we hold");
  const download = page.waitForEvent("download");
  await detail.getByRole("button", { name: "Download export" }).click();
  expect((await download).suggestedFilename()).toMatch(/^data-export-dr-0002-\d{4}-\d{2}-\d{2}/);
  await expect(page.getByTestId("export-preview")).toContainText("data_principal");
  await expect(page.getByTestId("export-preview")).toContainText("consents");
});

test("C104: the screen is closed to every role outside owner and tenant admin", async ({
  page,
}) => {
  await login(page, AUDITOR);
  const nav = page.getByTestId("side-nav");
  await expect(nav.getByRole("link", { name: "Audit log" })).toBeVisible();
  await expect(nav.getByRole("link", { name: "Data requests" })).toHaveCount(0);
  await page.goto("/admin/data-requests");
  await expect(page.getByTestId("forbidden-state")).toBeVisible();
});
