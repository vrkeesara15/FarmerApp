import { expect, test, type ConsoleMessage, type Page } from "@playwright/test";

/**
 * SEC-022: the console ships a strict CSP (nonce-based `script-src`, no `unsafe-inline`) plus
 * HSTS, nosniff, Referrer-Policy, Permissions-Policy, X-Frame-Options and COOP. The CSP comes
 * from middleware.ts (fresh nonce per request), the rest from next.config.ts.
 *
 * The specs also prove the app actually runs under the policy: nothing in a page load or a
 * basic interaction is refused by the browser.
 */

const CSP_VIOLATION = /Content Security Policy|Refused to (load|execute|apply|connect|run)/i;

/** Records browser CSP refusals (console errors and the securitypolicyviolation event). */
function watchCsp(page: Page): string[] {
  const violations: string[] = [];
  page.on("console", (msg: ConsoleMessage) => {
    if (msg.type() === "error" && CSP_VIOLATION.test(msg.text())) violations.push(msg.text());
  });
  page.on("pageerror", (err) => {
    if (CSP_VIOLATION.test(err.message)) violations.push(err.message);
  });
  return violations;
}

function directive(csp: string, name: string): string {
  const found = csp.split(";").find((d) => d.trim().startsWith(`${name} `));
  expect(found, `${name} missing from ${csp}`).toBeTruthy();
  return (found ?? "").trim().slice(name.length).trim();
}

test.describe("SEC-022 security headers", () => {
  test("every required header is on a page response, with a nonce and no unsafe-inline", async ({
    page,
  }) => {
    const violations = watchCsp(page);
    const response = await page.goto("/login");
    expect(response).not.toBeNull();
    const headers = response!.headers();

    expect(headers["x-content-type-options"]).toBe("nosniff");
    expect(headers["referrer-policy"]).toBe("strict-origin-when-cross-origin");
    expect(headers["x-frame-options"]).toBe("DENY");
    expect(headers["cross-origin-opener-policy"]).toBe("same-origin");
    for (const feature of ["camera", "microphone", "geolocation", "payment", "usb"])
      expect(headers["permissions-policy"]).toContain(`${feature}=()`);
    expect(headers["permissions-policy"]).toContain("interest-cohort=()");
    // `next start` runs with NODE_ENV=production, so HSTS is present.
    expect(headers["strict-transport-security"]).toBe(
      "max-age=31536000; includeSubDomains; preload",
    );
    expect(headers["x-powered-by"]).toBeUndefined();

    const csp = headers["content-security-policy"] ?? "";
    const scriptSrc = directive(csp, "script-src");
    expect(scriptSrc).toMatch(/'nonce-[A-Za-z0-9+/=]{16,}'/);
    expect(scriptSrc).toContain("'strict-dynamic'");
    expect(scriptSrc).not.toContain("unsafe-inline");
    expect(scriptSrc).not.toContain("unsafe-eval");
    expect(directive(csp, "default-src")).toBe("'self'");
    expect(directive(csp, "frame-ancestors")).toBe("'none'");
    expect(directive(csp, "object-src")).toBe("'none'");
    expect(directive(csp, "base-uri")).toBe("'self'");
    expect(directive(csp, "form-action")).toBe("'self'");
    expect(csp).toContain("upgrade-insecure-requests");

    // The nonce on the response header is the one stamped on the inline bootstrap scripts.
    const nonce = /'nonce-([^']+)'/.exec(scriptSrc)?.[1];
    expect(nonce).toBeTruthy();
    const inline = page.locator(`head script[nonce]`);
    expect(await inline.count()).toBeGreaterThanOrEqual(2);

    await expect(page.getByRole("heading", { name: "Sign in to the console" })).toBeVisible();
    expect(violations, violations.join("\n")).toEqual([]);
  });

  test("the nonce is fresh on every request", async ({ page }) => {
    const nonceOf = async (path: string) => {
      const res = await page.goto(path);
      const csp = res?.headers()["content-security-policy"] ?? "";
      return /'nonce-([^']+)'/.exec(csp)?.[1] ?? "";
    };
    const first = await nonceOf("/login");
    const second = await nonceOf("/login");
    expect(first).not.toBe("");
    expect(second).not.toBe(first);
  });

  test("a console page loads and stays interactive with the policy enforced", async ({ page }) => {
    const violations = watchCsp(page);
    const response = await page.goto("/home");
    const csp = response?.headers()["content-security-policy"] ?? "";
    expect(directive(csp, "script-src")).not.toContain("unsafe-inline");

    // The shell renders (signed out it asks to sign in) and hydration ran: the theme toggle,
    // the collapsible nav and the language menu are all client-side work under the CSP.
    await expect(page.getByTestId("side-nav")).toBeVisible();
    await expect(page.getByTestId("session-signed-out")).toBeVisible();
    const html = page.locator("html");
    const before = await html.getAttribute("data-theme");
    await page.getByTestId("theme-toggle").first().click();
    await expect(html).toHaveAttribute("data-theme", before === "dark" ? "light" : "dark");
    await page.getByTestId("side-nav-toggle").click();
    await expect(page.getByTestId("side-nav")).toHaveAttribute("data-collapsed", "true");
    await page.getByTestId("profile-menu-trigger").click();
    await expect(page.getByRole("menuitemradio").first()).toBeVisible();

    expect(violations, violations.join("\n")).toEqual([]);
  });

  test("static assets and the mock API carry the request-independent headers", async ({
    request,
  }) => {
    const api = await request.get("/api/mock/v1/health");
    expect(api.status()).toBe(200);
    expect(api.headers()["x-content-type-options"]).toBe("nosniff");
    expect(api.headers()["x-frame-options"]).toBe("DENY");
    // Route handlers go through the middleware too, so they carry the CSP as well.
    expect(directive(api.headers()["content-security-policy"] ?? "", "default-src")).toBe("'self'");

    // Static chunks are outside the middleware matcher but still get the static headers.
    const asset = await request.get("/_next/static/css", { failOnStatusCode: false });
    expect(asset.headers()["x-content-type-options"]).toBe("nosniff");
  });
});
