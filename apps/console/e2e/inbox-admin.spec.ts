import { expect, test, type Page } from "@playwright/test";

/**
 * WC-010 / WC-011 / WC-012 / WC-103 against the in-app mock API (lib/mock/flags.ts,
 * lib/mock/admin.ts): C70 inbox groups and SLA timers, C71 evidence + escalation + history and
 * the officer's explanation, C101 force logout and device rebind behind step-up (SEC-028), C102
 * settings with the live branding preview and the audit link, C103 filters, diff and export.
 * Serial: the steps share the mock state. OpenStreetMap tiles are blocked (offline run).
 */
test.describe.configure({ mode: "serial" });

const OWNERS = ["9876510001", "9876510002", "9876510003", "9876510004", "9876510005"] as const;
const FIELD_OFFICER = "9000000007";
const CLUSTER_HEAD = "9000000003";
const EXPLANATION = `Village meeting moved to the school (${Date.now().toString(36)})`;

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
  await expect(page.getByText(/Enter the 6-digit code we sent to \+91/)).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await dialog.getByTestId(`otp-${i}`).fill(d);
  await expect(dialog).toBeHidden();
}

test("C70: inbox groups by severity and rule, owners and live SLA timers", async ({ page }) => {
  await login(page, OWNERS[0]);
  await page.goto("/flags");
  await expect(page.getByRole("heading", { level: 1, name: "Flags" })).toBeVisible();

  const high = page.getByTestId("severity-group-high");
  await expect(high.getByRole("heading", { level: 2 })).toHaveText("High · 4");
  await expect(page.getByTestId("rule-group-high-VA-F06")).toContainText("VA-F06 · 2");
  await expect(page.getByTestId("severity-group-medium")).toBeVisible();
  await expect(page.getByTestId("count-high")).toContainText("4");

  // Every card has an owner and an SLA (WC-010 acceptance).
  const cards = page.getByTestId("flag-card");
  const n = await cards.count();
  expect(n).toBeGreaterThan(4);
  await expect(page.getByTestId("flag-owner")).toHaveCount(n);
  await expect(page.getByTestId("sla")).toHaveCount(n);

  // Overdue timers are in the danger colour; timers tick.
  const overdue = page.locator('[data-testid="sla"][data-overdue="true"]');
  await expect(overdue.first()).toContainText("Overdue by");
  await expect(overdue.first()).toHaveClass(/text-danger/);
  const burst = cards.filter({ hasText: "Registration burst" });
  await expect(burst.getByTestId("flag-owner")).toHaveText("Mahesh Goud (Cluster head)");
  await expect(burst.getByTestId("sla")).toHaveText(/^Due in \dh \d{2}m$/);
  // Under an hour the countdown shows seconds and ticks every second.
  const ticking = cards.filter({ hasText: "One device registered" }).getByTestId("sla");
  await expect(ticking).toHaveText(/^Overdue by \d+m \d{2}s$/);
  const before = await ticking.textContent();
  await expect(ticking).not.toHaveText(before ?? "", { timeout: 5000 });

  await page.getByLabel("Overdue only").check();
  await expect(page.getByTestId("flag-card")).toHaveCount(2);
  await expect(page.locator('[data-testid="sla"][data-overdue="false"]')).toHaveCount(0);
  await page.getByLabel("Overdue only").uncheck();
  await page.getByLabel("Rule").selectOption("VA-F03");
  await expect(page.getByTestId("flag-card")).toHaveCount(2);
});

test("C71: the officer adds an explanation to a flag about them", async ({ page }) => {
  await login(page, FIELD_OFFICER);
  await expect(page.getByRole("link", { name: "Users and roles" })).toHaveCount(0);
  await page.goto("/flags");
  const card = page.getByTestId("flag-card").filter({ hasText: "Registration burst" });
  await expect(page.getByTestId("flag-card")).toHaveCount(1);
  await card.getByRole("button", { name: "Open flag" }).click();
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Registration burst");
  // The subject reviews nothing.
  await expect(page.getByTestId("flag-actions")).toHaveCount(0);
  await page.getByLabel("Explain what happened").fill(EXPLANATION);
  await page.getByRole("button", { name: "Send explanation" }).click();
  await expect(
    page.getByTestId("subject-explanation").filter({ hasText: EXPLANATION }),
  ).toBeVisible();
});

test("C71: evidence map and photos, escalate with a note, history shows it", async ({ page }) => {
  await login(page, OWNERS[1]);
  await page.goto("/flags");
  await page
    .getByTestId("flag-card")
    .filter({ hasText: "Registration burst" })
    .getByRole("button", { name: "Open flag" })
    .click();
  await page.waitForURL("**/flags/*");
  await expect(page.getByTestId("flag-rule")).toHaveText("VA-F06 v1");
  await expect(page.getByTestId("flag-watchers")).toContainText("Farhan Ali");

  // Evidence bundle (VA-002): map points, photos from signed URLs, records, metrics.
  await expect(page.getByTestId("evidence-map")).toBeVisible();
  await expect(page.locator("path.evidence-point")).toHaveCount(3);
  await expect(page.getByTestId("evidence-photos").getByRole("img")).toHaveCount(2);
  await page.getByRole("button", { name: "Open evidence photo 1" }).click();
  await expect(
    page.getByRole("dialog").getByRole("img", { name: "Evidence photo 1" }),
  ).toBeVisible();
  await page.getByRole("dialog").getByRole("button", { name: "Close", exact: true }).click();
  await expect(
    page.getByTestId("evidence-records").getByRole("link", { name: "Ramesh Yadav" }),
  ).toHaveAttribute("href", /\/farmers\//);
  await expect(page.getByTestId("evidence-metrics")).toContainText("registrations");
  await expect(page.getByTestId("ai-summary")).toContainText("Automated summary — verify evidence");
  await expect(page.getByTestId("ai-summary")).toContainText("not available yet");

  // The officer's explanations stand out from review comments.
  const explanation = page.getByTestId("subject-explanation").filter({ hasText: EXPLANATION });
  await expect(explanation).toContainText("Explanation from the person flagged");
  await expect(page.getByTestId("review-comment")).toHaveCount(1);

  // State machine: open -> in review -> escalated (note required).
  const actions = page.getByTestId("flag-actions");
  await expect(actions.getByRole("button")).toHaveText(["Start review"]);
  await actions.getByRole("button", { name: "Start review" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Start review" }).click();
  await expect(page.getByTestId("flag-status").first()).toHaveText("In review");
  await expect(actions.getByRole("button")).toHaveText([
    "Data is valid",
    "Data corrected",
    "Escalate",
  ]);

  await actions.getByRole("button", { name: "Escalate" }).click();
  const dialog = page.getByRole("dialog");
  await dialog.getByRole("button", { name: "Escalate" }).click();
  await expect(dialog.getByText("Add a note that explains the decision.")).toBeVisible();
  await dialog
    .getByLabel("Note (required)")
    .fill("Same device used by two officers; auditor to check.");
  await dialog.getByRole("button", { name: "Escalate" }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByTestId("flag-status").first()).toHaveText("Escalated");
  await expect(page.getByTestId("flag-owner")).toContainText("Farhan Ali (Auditor)");
  await expect(actions.getByRole("button")).toHaveText(["Data corrected", "Action taken"]);

  const history = page.getByTestId("flag-history");
  await expect(history.locator("li").first()).toContainText(
    "You moved it from In review to Escalated",
  );
  await expect(history.locator("li").first()).toContainText("auditor to check");
});

test("C101: force logout and device rebind require step-up", async ({ page }) => {
  await login(page, OWNERS[2]);
  await page.goto("/admin/users");
  await expect(page.getByRole("heading", { level: 1, name: "Users and roles" })).toBeVisible();
  const row = page.getByRole("row").filter({ hasText: "Ravi Kumar" });
  await expect(row.getByTestId("device-status")).toHaveText("Waiting for approval");
  await row.getByRole("link", { name: "Ravi Kumar" }).click();
  await page.waitForURL("**/admin/users/u-field_officer");

  await page.getByRole("button", { name: "Force logout" }).click();
  const confirm = page.getByRole("dialog").filter({ hasText: "Sign Ravi Kumar out everywhere?" });
  await expect(confirm.getByTestId("confirm-step-up-note")).toBeVisible();
  await confirm.getByRole("button", { name: "Sign out everywhere" }).click();
  await stepUp(page);
  await expect(page.getByText("Ravi Kumar was signed out of every device")).toBeVisible();
  await expect(confirm).toBeHidden();

  // The 5-minute token is reused (memory only): rebinding asks for a confirmation, not a code.
  const devices = page.getByTestId("devices");
  await devices
    .getByRole("row")
    .filter({ hasText: "Samsung Galaxy M14" })
    .getByRole("button", { name: "Bind this device" })
    .click();
  const bind = page.getByRole("dialog").filter({ hasText: "Bind Samsung Galaxy M14?" });
  await expect(bind).toContainText("Their current phone is unbound and signed out.");
  await bind.getByRole("button", { name: "Bind device" }).click();
  await expect(bind).toBeHidden();
  await expect(page.getByTestId("step-up-dialog")).toHaveCount(0);
  await expect(
    devices.getByRole("row").filter({ hasText: "Samsung Galaxy M14" }).getByTestId("device-status"),
  ).toHaveText("Bound");
  await expect(
    devices.getByRole("row").filter({ hasText: "Redmi Note 12" }).getByTestId("device-status"),
  ).toHaveText("Unbound");

  // After a reload the token is gone: the next admin action asks again.
  await page.reload();
  await page.getByRole("button", { name: "Force logout" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Sign out everywhere" }).click();
  await expect(page.getByTestId("step-up-dialog")).toBeVisible();
});

test("C102: branding preview is live; a change needs step-up and links to the audit", async ({
  page,
}) => {
  await login(page, OWNERS[3]);
  await page.goto("/settings");
  await expect(page.getByRole("heading", { level: 1, name: "Settings" })).toBeVisible();
  await expect(page.getByLabel("Travel allowance per km")).toHaveValue("3");
  await expect(page.getByLabel("Minimum visit time")).toHaveValue("5");

  // Live preview of both apps follows the unsaved form.
  await expect(page.getByTestId("preview-agent-name")).toHaveText("Mitra");
  await page.getByLabel("Field agent app name").fill("FCC Mitra");
  await expect(page.getByTestId("preview-agent-name")).toHaveText("FCC Mitra");
  await page.getByLabel("Farmer app name").fill("FCC Kisan");
  await expect(page.getByTestId("preview-farmer-name")).toHaveText("FCC Kisan");
  await page.getByLabel("Primary colour", { exact: true }).fill("#AA3300");
  await expect(page.getByTestId("preview-agent-header")).toHaveAttribute("data-colour", "#AA3300");
  await expect(page.getByTestId("preview-farmer-header")).toHaveAttribute("data-colour", "#AA3300");
  // FA-008: the preview paints the *derived* palette, so a colour that would be unreadable
  // shows here already corrected — exactly the colour the officer's phone will paint.
  await page.getByLabel("Primary colour", { exact: true }).fill("#FFCC00");
  await expect(page.getByTestId("preview-agent-header")).toHaveAttribute("data-colour", "#876C00");
  await page.getByLabel("Primary colour", { exact: true }).fill("#AA3300");
  await page.getByLabel("Support phone").fill("+918000000000");
  await expect(page.getByTestId("preview-support")).toHaveText("Help: +918000000000");

  // Validation mirrors the API ranges before anything is sent.
  await page.getByLabel("Geofence radius").fill("5");
  await page.getByRole("button", { name: "Save settings" }).click();
  await expect(page.getByText("Enter a whole number from 10 to 2000 m.")).toBeVisible();
  await expect(page.getByTestId("step-up-dialog")).toHaveCount(0);
  await page.getByLabel("Geofence radius").fill("200");
  await page.getByRole("button", { name: "Save settings" }).click();
  await stepUp(page);
  const saved = page.getByTestId("settings-saved");
  await expect(saved).toContainText("Saved and audited.");

  await saved.getByRole("link", { name: "View in the audit log" }).click();
  await page.waitForURL(/\/admin\/audit\?entity=tenant&action=tenant_settings\.update$/);
  const row = page.getByRole("row").filter({ hasText: "tenant_settings.update" }).first();
  await expect(row).toContainText("geofence_radius_m");
  await row.getByRole("button", { name: "Show changes of tenant_settings.update" }).click();
  const diff = page.getByTestId("audit-diff").first();
  const geofence = diff.getByTestId("diff-row").filter({ hasText: "geofence_radius_m" });
  await expect(geofence).toHaveAttribute("data-changed", "true");
  await expect(geofence.getByRole("cell").nth(0)).toHaveText("150");
  await expect(geofence.getByRole("cell").nth(1)).toHaveText("200");
});

test("C103: audit filters, diff and CSV export behind step-up", async ({ page }) => {
  await login(page, OWNERS[4]);
  await page.goto("/admin/audit");
  await expect(page.getByRole("heading", { level: 1, name: "Audit log" })).toBeVisible();
  await page.getByLabel("Entity", { exact: true }).fill("device");
  await page
    .getByTestId("audit-filters")
    .getByRole("button", { name: "Apply", exact: true })
    .click();
  await page.waitForURL(/\/admin\/audit\?entity=device$/);
  const rows = page.getByTestId("data-table").locator("tbody tr");
  await expect(rows.first()).toContainText("device.");
  for (const text of await rows.allTextContents()) expect(text).toMatch(/device\./);

  await page.getByLabel("Action", { exact: true }).fill("device.report_lost");
  await page
    .getByTestId("audit-filters")
    .getByRole("button", { name: "Apply", exact: true })
    .click();
  const lost = page.getByRole("row").filter({ hasText: "device.report_lost" }).first();
  await lost.getByRole("button", { name: /Show changes/ }).click();
  const diff = page.getByTestId("audit-diff");
  await expect(diff.getByTestId("diff-row").filter({ hasText: "device_id" })).toContainText(
    "android-5b2e10",
  );
  await expect(page.getByText("IP address:")).toBeVisible();

  await page.getByRole("button", { name: "Export CSV" }).click();
  const download = page.waitForEvent("download");
  await stepUp(page);
  expect((await download).suggestedFilename()).toBe("audit-log.csv");
  await expect(page.getByText("Audit log exported")).toBeVisible();
});

test("roles: cluster heads get no settings or audit, and a graceful 403", async ({ page }) => {
  await login(page, CLUSTER_HEAD);
  const nav = page.getByTestId("side-nav");
  await expect(nav.getByRole("link", { name: "Flags" })).toBeVisible();
  await expect(nav.getByRole("link", { name: "Users and roles" })).toBeVisible();
  await expect(nav.getByRole("link", { name: "Settings" })).toHaveCount(0);
  await expect(nav.getByRole("link", { name: "Audit log" })).toHaveCount(0);
  await page.goto("/settings");
  await expect(page.getByTestId("forbidden-state")).toBeVisible();
  await page.goto("/admin/audit");
  await expect(page.getByTestId("forbidden-state")).toBeVisible();
  // Read-only users list: no create, no security actions.
  await page.goto("/admin/users");
  await expect(page.getByRole("button", { name: "New user" })).toHaveCount(0);
});
