import type { NextConfig } from "next";
import { staticSecurityHeaders } from "./lib/security-headers";

// SEC-022: request-independent headers for every response (documents, /api/* route handlers
// and /_next/static/*). The Content-Security-Policy is NOT here — it needs a per-request nonce
// and is set by middleware.ts; no header is set in both places.
const securityHeaders = Object.entries(
  staticSecurityHeaders({ dev: process.env.NODE_ENV !== "production" }),
).map(([key, value]) => ({ key, value }));

const nextConfig: NextConfig = {
  reactStrictMode: true,
  output: "standalone", // apps/console/Dockerfile ships .next/standalone (M5)
  poweredByHeader: false,
  eslint: { ignoreDuringBuilds: true }, // `npm run lint` runs ESLint explicitly in `check`
  typescript: { ignoreBuildErrors: false },
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
