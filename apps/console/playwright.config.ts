import { defineConfig, devices } from "@playwright/test";

/**
 * Smoke test against `next start` (production build) with the in-app mock API
 * (NEXT_PUBLIC_API_URL unset -> /api/mock). Run `npm run build` before `npm run test:e2e`;
 * CI does this via `npm run check` first. Set PW_BUILD=1 to build inside the web server step.
 */
const port = Number(process.env.PORT ?? 3100);
const build = process.env.PW_BUILD === "1";

export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: `http://localhost:${port}`,
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: `${build ? "npm run build && " : ""}npm run start -- --port ${port}`,
    url: `http://localhost:${port}/login`,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
  },
});
