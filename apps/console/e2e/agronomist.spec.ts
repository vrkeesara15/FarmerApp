import { expect, test, type Page } from "@playwright/test";

/**
 * WC-006 / WC-007 against the in-app mock API (lib/mock/diagnosis.ts): C60 review queue with SLA
 * countdowns, candidates, the LLM suggestion and provenance, a correction that notifies the
 * farmer and officer; C61 create a problem, chunked image upload, draft -> reviewed -> approved
 * with the corpus version bump, the production filter, retire; owners read C60-C62 only.
 * Serial: the steps share the mock state.
 */
test.describe.configure({ mode: "serial" });

const AGRONOMIST = "9000000008";
const OWNER = "9876520001";

/** A 1x1 PNG (the mock stores the bytes and serves them back as the signed URL). */
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkqPhfDwAEhQHMzs9D1QAAAABJRU5ErkJggg==",
  "base64",
);

async function login(page: Page, phone: string) {
  await page.goto("/login");
  await page.getByLabel("Mobile number").fill(phone);
  await page.getByRole("button", { name: "Send OTP" }).click();
  await expect(page.getByTestId("login-otp-step")).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
  await page.waitForURL("**/home");
}

test("C60: review queue -> open a provisional diagnosis -> correct it -> farmer notified", async ({
  page,
}) => {
  await login(page, AGRONOMIST);
  await expect(page.getByRole("link", { name: "Agronomist" })).toBeVisible();
  await page.getByRole("link", { name: "Agronomist" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Review queue" })).toBeVisible();

  // Oldest first with the DX-006 countdown: > 24 h breached, 18-24 h warning, else due in.
  const items = page.getByTestId("queue-item");
  await expect(items).toHaveCount(5);
  await expect(page.getByTestId("queue-total")).toHaveText("5 waiting");
  await expect(page.getByTestId("queue-overdue")).toHaveText("2 past 18 h");
  const slas = page.getByTestId("queue-list").getByTestId("review-sla");
  await expect(slas.nth(0)).toHaveAttribute("data-level", "breach");
  await expect(slas.nth(0)).toContainText("SLA breached");
  await expect(slas.nth(0)).toHaveClass(/text-danger/);
  await expect(slas.nth(1)).toHaveAttribute("data-level", "warning");
  await expect(slas.nth(1)).toContainText("18 h alert · due in 4h");
  await expect(slas.nth(2)).toHaveAttribute("data-level", "ok");

  // Filters: flagged only, then clear.
  await page.getByLabel("Flagged only").check();
  await expect(items).toHaveCount(1);
  await page.getByRole("button", { name: "Clear" }).click();
  await expect(items).toHaveCount(5);

  // Open the provisional paddy case the LLM called rice blast.
  await items.filter({ hasText: "Provisional" }).filter({ hasText: "Paddy" }).click();
  const detail = page.getByTestId("review-detail");
  await expect(detail.getByRole("heading", { level: 2 })).toHaveText("Paddy · Rice blast");

  // Farm context only (no farmer identity).
  const ctx = page.getByTestId("farm-context");
  await expect(ctx).toContainText("Warangal");
  await expect(ctx).toContainText("Kharif");
  await expect(ctx).toContainText("Vegetative");

  // Photo gallery with zoom.
  await page.getByRole("button", { name: "Open photo 1" }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog.getByRole("img", { name: "Farmer photo 1" })).toBeVisible();
  await dialog.getByRole("button", { name: "Zoom in" }).click();
  await expect(page.getByTestId("zoom-level")).toHaveText("150%");
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();

  // Candidates with similarity and vote share, the LLM suggestion and the provenance.
  const rows = page.getByTestId("candidate-row");
  await expect(rows).toHaveCount(2);
  await expect(rows.nth(0)).toContainText("Rice blast");
  await expect(rows.nth(0).getByTestId("candidate-score")).toHaveText("0.912");
  await expect(rows.nth(0).getByTestId("candidate-share")).toHaveText("60%");
  await expect(rows.nth(1).getByTestId("candidate-share")).toHaveText("40%");
  await expect(page.getByTestId("llm-label")).toHaveText("Automated suggestion — verify");
  await expect(page.getByTestId("llm-reasoning")).toContainText("Spindle-shaped lesions");
  const prov = page.getByTestId("provenance");
  await expect(prov).toContainText("siglip-base-patch16-224@2024-01");
  await expect(prov).toContainText("ondevice-v1.0");
  await expect(prov).toContainText("claude-opus-5");
  await expect(prov).toContainText("7");

  // Correct requires a problem; the picker is searchable in local names.
  const form = page.getByTestId("review-form");
  await form.getByLabel("Correct label").check();
  await form
    .getByLabel("Note for the record")
    .fill("Rusty diffuse spots on old leaves: zinc, not blast.");
  await form.getByRole("button", { name: "Submit review" }).click();
  await expect(form.getByText("Pick the correct problem.")).toBeVisible();
  await form.getByLabel("Search problems in any language").fill("జింక్");
  const picker = page.getByTestId("problem-picker");
  await expect(picker.getByRole("radio")).toHaveCount(1);
  await picker.getByRole("radio").check();
  await form.getByLabel(/Add these photos to the corpus/).check();
  await form.getByRole("button", { name: "Submit review" }).click();

  const done = page.getByTestId("review-done");
  await expect(done).toBeVisible();
  await expect(page.getByTestId("review-result")).toHaveText(
    "The farmer now sees: Zinc deficiency (khaira) (Corrected).",
  );
  await expect(page.getByTestId("review-notified")).toHaveText(
    "The farmer and their field officer have been notified.",
  );
  await expect(page.getByTestId("review-corpus-added")).toHaveText(
    "2 photos added to the corpus as reviewed images.",
  );
  await expect(page.getByTestId("queue-total")).toHaveText("4 waiting");
  await expect(items).toHaveCount(4);
});

test("C61: create a problem, upload an image, approve it and see the version bump", async ({
  page,
}) => {
  await login(page, AGRONOMIST);
  await page.goto("/agronomist/corpus");
  await expect(page.getByRole("heading", { level: 1, name: "Corpus manager" })).toBeVisible();
  await expect(page.getByTestId("production-note")).toContainText(
    "Only approved entries are used in production",
  );
  const versionBadge = page.getByTestId("corpus-version");
  await expect(versionBadge).toHaveText(/^Corpus version \d+$/);
  const version = Number((await versionBadge.textContent())!.replace(/\D/g, ""));

  // Create: crop + pest from the product master, names per language, symptoms.
  await page.getByRole("button", { name: "New problem" }).click();
  const dlg = page.getByTestId("problem-dialog");
  await dlg.getByLabel("Crop").selectOption({ label: "Paddy" });
  await dlg.getByLabel("Pest or disease").selectOption({ label: "Brown planthopper" });
  await expect(page.getByTestId("problem-type")).toHaveText("Type: Pest");
  await dlg.getByLabel("Name (English)").fill("Brown planthopper");
  await dlg
    .getByLabel(/Symptoms in English/)
    .fill("Hopper burn patches\nInsects at the base of tillers");
  await dlg.getByRole("radio", { name: "Telugu" }).click();
  await dlg.getByLabel("Name (Telugu)").fill("సుడిదోమ");
  await expect(page.getByTestId("missing-langs")).toHaveText("Missing: Kannada, Hindi, Marathi");
  await page.getByRole("button", { name: "Save" }).click();
  await expect(dlg).toBeHidden();

  const detail = page.getByTestId("problem-detail");
  await expect(detail.getByRole("heading", { level: 2 })).toHaveText("Brown planthopper · Paddy");
  await expect(detail.getByTestId("corpus-status-draft").first()).toBeVisible();
  await expect(page.getByTestId("problem-names")).toContainText("సుడిదోమ");

  // Upload (chunked, purpose corpus) then attach: the server embeds it.
  const upload = page.getByTestId("image-upload");
  await upload
    .getByLabel("Image file")
    .setInputFiles({ name: "bph.png", mimeType: "image/png", buffer: PNG });
  await upload.getByLabel("Region").fill("Warangal");
  await upload.getByLabel("Season").selectOption({ label: "Kharif" });
  await upload.getByRole("button", { name: "Upload image" }).click();
  const image = page.getByTestId("corpus-image");
  await expect(image).toHaveCount(1);
  await expect(image.getByTestId("embedding-status")).toHaveText(
    "Embedded · siglip-base-patch16-224@2024-01",
  );
  await expect(image.getByTestId("image-meta")).toContainText("Leaf");
  await expect(image.getByTestId("image-meta")).toContainText("Warangal");
  await expect(image.getByRole("img")).toHaveAttribute("src", /^data:image\/png;base64,/);

  // Draft -> reviewed (image and problem); draft never offers "Approve".
  const problemActions = page.getByTestId("problem-actions");
  await expect(problemActions.getByRole("button", { name: "Approve" })).toHaveCount(0);
  await image.getByRole("button", { name: "Mark reviewed" }).click();
  await expect(image).toHaveAttribute("data-status", "reviewed");
  await problemActions.getByRole("button", { name: "Mark reviewed" }).click();
  await expect(detail.getByTestId("corpus-status-reviewed").first()).toBeVisible();

  // Reviewed -> approved: the human gate, then one version bump for problem + image.
  await problemActions.getByRole("button", { name: "Approve" }).click();
  const move = page.getByTestId("move-dialog");
  await expect(page.getByTestId("approve-bump")).toContainText(
    `moves the corpus from version ${version} to ${version + 1}`,
  );
  await expect(move.getByLabel("Also approve the 1 reviewed images of this problem")).toBeChecked();
  await page.getByRole("button", { name: "Approve and publish" }).click();
  await expect(page.getByRole("dialog").getByRole("alert")).toContainText("regulatory human gate");
  await move.getByLabel("I have verified this entry").check();
  await page.getByRole("button", { name: "Approve and publish" }).click();
  await expect(move).toBeHidden();
  await expect(versionBadge).toHaveText(`Corpus version ${version + 1}`);
  await expect(detail.getByTestId("corpus-status-approved").first()).toBeVisible();
  await expect(image).toHaveAttribute("data-status", "approved");
  await expect(page.getByTestId("version-row").first()).toContainText(`v${version + 1}`);
  await expect(page.getByTestId("version-row").first()).toContainText("Current");
  await expect(page.getByTestId("version-row").first()).toContainText(
    "1 problems · 1 images · 0 retired",
  );
  await expect(detail.getByRole("button", { name: "Edit" })).toHaveCount(0);

  // What production uses: approved problems only, with their served images.
  await page.getByLabel("Show what production uses").check();
  const rows = page.getByTestId("corpus-row");
  await expect(rows.filter({ hasText: "Brown planthopper" })).toHaveCount(1);
  await expect(
    page.locator('[data-testid="corpus-row"]:not([data-status="approved"])'),
  ).toHaveCount(0);
  await expect(
    rows.filter({ hasText: "Brown planthopper" }).getByTestId("served-count"),
  ).toHaveText("1");
  expect(await rows.count()).toBeGreaterThan(1);
  await page.getByLabel("Show what production uses").uncheck();
  await expect(page.locator('[data-testid="corpus-row"][data-status="draft"]')).not.toHaveCount(0);

  // Retiring what production serves bumps the version again (and frees the pair for reruns).
  await problemActions.getByRole("button", { name: "Retire" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Retire" }).click();
  await expect(versionBadge).toHaveText(`Corpus version ${version + 2}`);
  await expect(detail.getByTestId("corpus-status-retired").first()).toBeVisible();
  await expect(problemActions).toHaveCount(0);
});

test("owners read C60-C62 without review or workflow actions", async ({ page }) => {
  await login(page, OWNER);
  await page.getByRole("link", { name: "Agronomist" }).click();
  await expect(page.getByTestId("read-only-note")).toBeVisible();
  await expect(page.getByTestId("review-detail")).toBeVisible();
  await expect(page.getByTestId("candidates")).toBeVisible();
  await expect(page.getByTestId("review-form")).toHaveCount(0);
  await expect(page.getByTestId("owner-note")).toHaveText(
    "Owners can read the queue; only agronomists review.",
  );

  await page.getByRole("link", { name: "Corpus" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Corpus manager" })).toBeVisible();
  await expect(page.getByRole("button", { name: "New problem" })).toHaveCount(0);
  await page.getByRole("button", { name: "Open Rice blast" }).first().click();
  await expect(page.getByTestId("problem-detail")).toBeVisible();
  await expect(page.getByTestId("problem-actions")).toHaveCount(0);
  await expect(page.getByTestId("image-actions")).toHaveCount(0);
  await expect(page.getByTestId("image-upload")).toHaveCount(0);

  await page.getByRole("link", { name: "Diagnosis quality" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Diagnosis quality" })).toBeVisible();
  // AN-007: the figures come from `GET /v1/diagnoses/quality`, not from the browser.
  await expect(page.getByTestId("kpi-card")).toHaveCount(4);
  await expect(page.getByTestId("quality-sources")).toContainText("Corpus");
  await expect(page.getByTestId("quality-statuses")).toContainText("Confirmed");
  await expect(page.getByTestId("quality-review")).toContainText("Average");
  await expect(page.getByTestId("unknown-row").first()).toBeVisible();
  await expect(page.getByTestId("eval-top1")).toBeVisible();
});
