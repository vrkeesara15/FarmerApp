import { expect, test, type Page } from "@playwright/test";

/**
 * WC-005 console flow against the in-app mock API (lib/mock/catalog.ts): C50 product + SKU,
 * C51 draft claim -> agronomist approval (human gate) -> recommendable -> retired -> gone,
 * C52 price rules. Serial: the steps share the mock catalogue.
 */
test.describe.configure({ mode: "serial" });

// Any number signs in as the owner in the mock; one number per test keeps each well under
// the mock's 3-resends-per-15-minutes limit (the smoke tests use 9876543210).
const OWNERS = ["9876500001", "9876500002", "9876500003"] as const;
const AGRONOMIST = "9000000008";
const suffix = `${Date.now().toString(36)}`;
const PRODUCT = `E2E Guard ${suffix}`;
const SKU_LABEL = `${PRODUCT} · 250 ml`;
const BARCODE = `890${Date.now().toString().slice(-10)}`;

async function login(page: Page, phone: string) {
  await page.goto("/login");
  await page.getByLabel("Mobile number").fill(phone);
  await page.getByRole("button", { name: "Send OTP" }).click();
  await expect(page.getByTestId("login-otp-step")).toBeVisible();
  for (const [i, d] of [..."123456"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
  await page.waitForURL("**/home");
}

test("C50: owner creates a product and a SKU", async ({ page }) => {
  await login(page, OWNERS[0]);
  await page.goto("/products");
  await expect(page.getByRole("heading", { level: 1, name: "Products" })).toBeVisible();
  await expect(page.getByRole("row").filter({ hasText: "FCC Imida" })).toBeVisible();

  await page.getByRole("button", { name: "New product" }).click();
  const dialog = page.getByRole("dialog");
  // Client-side validation mirrors the API (HSN 4/6/8 digits).
  await dialog.getByLabel("Product name").fill(PRODUCT);
  await dialog.getByLabel("Brand", { exact: true }).fill("E2E Agro");
  await dialog.getByLabel("HSN code").fill("38089");
  await dialog.getByRole("button", { name: "Save" }).click();
  await expect(dialog.getByText("HSN must have 4, 6 or 8 digits")).toBeVisible();
  await dialog.getByLabel("HSN code").fill("3808");
  await dialog.getByLabel("Active ingredient").fill("Chlorantraniliprole 18.5% SC");
  await dialog.getByRole("button", { name: "Save" }).click();
  await expect(dialog).toBeHidden();

  const row = page.getByRole("row").filter({ hasText: PRODUCT });
  await expect(row).toBeVisible();
  await row.getByRole("button", { name: `Add a SKU to ${PRODUCT}` }).click();
  const skuDialog = page.getByRole("dialog");
  await skuDialog.getByLabel("Pack size").fill("250");
  await skuDialog.getByLabel("Unit").selectOption("ml");
  // A barcode already used by another SKU is rejected by the API (409 barcode_exists).
  await skuDialog.getByLabel("Barcode").fill("8901000000011");
  await skuDialog.getByLabel("MRP").fill("400");
  await skuDialog.getByRole("button", { name: "Save" }).click();
  await expect(
    skuDialog.getByText("This barcode is already used by another SKU.").first(),
  ).toBeVisible();
  await skuDialog.getByLabel("Barcode").fill(BARCODE);
  await skuDialog.getByRole("button", { name: "Save" }).click();
  await expect(skuDialog).toBeHidden();

  await row.getByRole("button", { name: `Show SKUs of ${PRODUCT}` }).click();
  await expect(page.getByTestId("sku-row").filter({ hasText: "250 ml" })).toHaveCount(1);
});

test("C51: owner creates a draft claim but cannot approve it", async ({ page }) => {
  await login(page, OWNERS[1]);
  await page.goto("/products/label-claims");
  await expect(page.getByRole("heading", { level: 1, name: "Label claims" })).toBeVisible();

  await page.getByRole("button", { name: "New claim" }).click();
  const dialog = page.getByRole("dialog");
  await dialog.getByTestId("claim-sku").selectOption({ label: SKU_LABEL });
  await dialog.getByTestId("claim-crop").selectOption({ label: "Paddy" });
  await dialog.getByTestId("claim-pest").selectOption({ label: "Brown planthopper" });
  await dialog.getByLabel("Dose per acre").fill("60 ml");
  await dialog.getByLabel("Dose value").fill("0");
  await dialog.getByLabel("Pre-harvest interval (days)").fill("21");
  await dialog.getByRole("button", { name: "Save draft" }).click();
  await expect(dialog.getByText("Enter a number greater than 0")).toBeVisible();
  await expect(dialog.getByText("The CIB&RC source reference is required")).toBeVisible();

  await dialog.getByLabel("Dose value").fill("60");
  await dialog.getByLabel("Dose per 15 L tank").fill("4.5 ml");
  await dialog.getByLabel("Protective equipment (PPE)").fill("Gloves and mask");
  await dialog.getByLabel("Source reference").fill(`CIB-E2E-${suffix}`);
  await dialog.getByRole("button", { name: "Save draft" }).click();
  await expect(dialog).toBeHidden();

  const row = page.getByRole("row").filter({ hasText: SKU_LABEL });
  await expect(row.getByTestId("claim-status-draft")).toBeVisible();
  await expect(row.getByRole("button", { name: "Approve", exact: true })).toHaveCount(0);
  await expect(row.getByRole("button", { name: "Retire", exact: true })).toBeVisible();
});

test("C51: agronomist approves, the SKU becomes recommendable, retiring removes it", async ({
  page,
}) => {
  await login(page, AGRONOMIST);
  await page.goto("/products/label-claims");

  const preview = page.getByTestId("recommendation-preview");
  await preview.getByTestId("preview-crop").selectOption({ label: "Paddy" });
  await preview.getByTestId("preview-pest").selectOption({ label: "Brown planthopper" });
  // The seeded approved claim is there; the draft is not recommendable.
  await expect(
    preview.getByTestId("recommendable-sku").filter({ hasText: "FCC Imida" }),
  ).toBeVisible();
  await expect(preview.getByTestId("recommendable-sku").filter({ hasText: PRODUCT })).toHaveCount(
    0,
  );

  const row = page.getByRole("row").filter({ hasText: SKU_LABEL });
  await row.getByRole("button", { name: "Approve", exact: true }).click();
  const confirm = page.getByRole("dialog");
  await expect(confirm.getByText(/Approval is a regulatory decision/)).toBeVisible();
  await expect(confirm.getByTestId("claim-summary")).toContainText(`CIB-E2E-${suffix}`);
  await confirm.getByRole("button", { name: "Approve claim" }).click();
  await expect(confirm).toBeHidden();
  await expect(row.getByTestId("claim-status-approved")).toBeVisible();

  const recommended = preview.getByTestId("recommendable-sku").filter({ hasText: PRODUCT });
  await expect(recommended).toBeVisible();
  await expect(recommended).toContainText("60 ml");
  await expect(recommended).toContainText("4.5 ml");
  await expect(recommended).toContainText("21 days");
  await expect(recommended).toContainText("Gloves and mask");

  // Version history drawer lists the approved version.
  await row.getByRole("button", { name: "Version history" }).click();
  const drawer = page.getByTestId("history-drawer");
  await expect(drawer.getByTestId("history-version")).toHaveCount(1);
  await page.keyboard.press("Escape");
  await expect(drawer).toBeHidden();

  await row.getByRole("button", { name: "Retire", exact: true }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Retire claim" }).click();
  await expect(row.getByTestId("claim-status-retired")).toBeVisible();
  await expect(recommended).toHaveCount(0);
  await expect(
    preview.getByTestId("recommendable-sku").filter({ hasText: "FCC Imida" }),
  ).toBeVisible();
});

test("C52: price above MRP and overlapping ranges are rejected per row", async ({ page }) => {
  await login(page, OWNERS[2]);
  await page.goto("/products/prices");
  await expect(page.getByRole("heading", { level: 1, name: "Price lists" })).toBeVisible();
  await expect(page.getByRole("row").filter({ hasText: "FCC Imida · 100 ml" })).toBeVisible();

  // Above MRP (₹400) for the new SKU.
  await page.getByRole("button", { name: "Add price" }).click();
  await page.getByTestId("price-sku-new-1").selectOption({ label: SKU_LABEL });
  await page.getByTestId("price-price-new-1").fill("450");
  await page.getByTestId("price-save").click();
  await expect(page.getByTestId("price-error-new-1")).toHaveText("The price is above the MRP.");

  // Within MRP but overlapping the open-ended default of the seeded SKU: the API says 409.
  await page.getByTestId("price-sku-new-1").selectOption({ label: "FCC Imida · 100 ml" });
  await page.getByTestId("price-price-new-1").fill("200");
  await page.getByTestId("price-save").click();
  await expect(page.getByTestId("price-error-new-1")).toHaveText(
    "This date range overlaps another price for the same SKU.",
  );

  // A valid price for the new SKU saves.
  await page.getByTestId("price-sku-new-1").selectOption({ label: SKU_LABEL });
  await page.getByTestId("price-price-new-1").fill("380");
  await page.getByTestId("price-save").click();
  const saved = page.getByRole("row").filter({ hasText: SKU_LABEL });
  await expect(saved).toContainText("380");
  await expect(page.getByTestId("price-error-new-1")).toHaveCount(0);

  // Store overrides live in their own list.
  await page.getByTestId("price-store").selectOption({ label: "Warangal (WGL)" });
  await expect(page.getByRole("row").filter({ hasText: "FCC Imida · 100 ml" })).toHaveCount(1);
  await expect(page.getByRole("row").filter({ hasText: SKU_LABEL })).toHaveCount(0);
});
