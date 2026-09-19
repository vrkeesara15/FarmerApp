import { expect, test } from "@playwright/test";

test.describe("console smoke (mock API)", () => {
  test("login page renders and OTP flow reaches the shell", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByRole("heading", { name: "Sign in to the console" })).toBeVisible();
    await expect(page.getByTestId("login-phone-step")).toBeVisible();

    await page.getByLabel("Mobile number").fill("9876543210");
    await page.getByRole("button", { name: "Send OTP" }).click();
    await expect(page.getByTestId("login-otp-step")).toBeVisible();

    // Type the mock OTP box by box; onComplete submits automatically.
    for (const [i, d] of [..."123456"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
    await page.waitForURL("**/home");

    await expect(page.getByTestId("side-nav")).toBeVisible();
    await expect(page.getByTestId("top-bar")).toBeVisible();
    await expect(page.getByRole("heading", { level: 1, name: "Home" })).toBeVisible();
  });

  test("wrong OTP shows an error from problem+json", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel("Mobile number").fill("9876543210");
    await page.getByRole("button", { name: "Send OTP" }).click();
    for (const [i, d] of [..."000000"].entries()) await page.getByTestId(`otp-${i}`).fill(d);
    await expect(page.getByRole("alert").filter({ hasText: "Sign-in failed" })).toBeVisible();
  });

  test("shell routes render EmptyState and theme toggles", async ({ page }) => {
    for (const path of ["/home", "/field-team", "/farmers", "/stores", "/agronomist"]) {
      await page.goto(path);
      await expect(page.getByTestId("empty-state")).toBeVisible();
    }
    // C70 / C101 / C102 / C103 are data screens (WC-010-012, WC-103): signed out they ask to sign in.
    for (const path of ["/flags", "/admin/users", "/settings", "/admin/audit"]) {
      await page.goto(path);
      await expect(page.getByTestId("session-signed-out")).toBeVisible();
    }
    // C50 is a real data screen (WC-005): without a session it asks to sign in again.
    await page.goto("/products");
    await expect(page.getByRole("heading", { level: 1, name: "Products" })).toBeVisible();
    await expect(page.getByTestId("session-signed-out")).toBeVisible();
    await page.goto("/home");
    const html = page.locator("html");
    await expect(html).toHaveAttribute("data-theme", /light|dark/);
    const before = await html.getAttribute("data-theme");
    await page.getByTestId("theme-toggle").first().click();
    await expect(html).toHaveAttribute("data-theme", before === "dark" ? "light" : "dark");
    await page.reload();
    await expect(html).toHaveAttribute("data-theme", before === "dark" ? "light" : "dark");
    // Collapse the nav.
    await page.getByTestId("side-nav-toggle").click();
    await expect(page.getByTestId("side-nav")).toHaveAttribute("data-collapsed", "true");
  });

  test("language switch from the profile menu is live, sets html lang and persists", async ({
    page,
  }) => {
    await page.goto("/home");
    await expect(page.getByRole("heading", { level: 1, name: "Home" })).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("lang", "en");

    await page.getByTestId("profile-menu-trigger").click();
    const items = page.getByRole("menuitemradio");
    await expect(items).toHaveCount(5);
    await expect(items.nth(1)).toContainText("తెలుగు");
    await items.nth(1).click();

    // No navigation or reload: the same page is Telugu now (FA-004).
    await expect(page.getByRole("heading", { level: 1, name: "హోమ్" })).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("lang", "te");
    await expect(page.getByRole("link", { name: "రైతులు" })).toBeVisible();

    await page.reload();
    await expect(page.locator("html")).toHaveAttribute("lang", "te");
    await expect(page.getByRole("heading", { level: 1, name: "హోమ్" })).toBeVisible();

    // Back to English through the menu (Hindi first, to prove Devanagari renders too).
    await page.getByTestId("profile-menu-trigger").click();
    await page.getByTestId("locale-hi").click();
    await expect(page.getByRole("heading", { level: 1, name: "होम" })).toBeVisible();
    await page.getByTestId("profile-menu-trigger").click();
    await page.getByTestId("locale-en").click();
    await expect(page.getByRole("heading", { level: 1, name: "Home" })).toBeVisible();
  });

  test("design gallery renders every component in both themes", async ({ page }) => {
    await page.goto("/design");
    await expect(page.getByRole("heading", { level: 1, name: "Design system" })).toBeVisible();
    const light = page.getByTestId("gallery-light");
    const dark = page.getByTestId("gallery-dark");
    await expect(light).toBeVisible();
    await expect(dark).toBeVisible();
    await expect(dark).toHaveAttribute("data-theme", "dark");
    for (const name of ["AppButton", "OtpInput", "DataTable", "FlagCard", "TopBar", "SideNav"]) {
      await expect(light.getByRole("heading", { level: 2, name, exact: true })).toBeVisible();
      await expect(dark.getByRole("heading", { level: 2, name, exact: true })).toBeVisible();
    }
    await expect(page.getByTestId("empty-state").first()).toBeVisible();
  });
});
