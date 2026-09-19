import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  output: "standalone", // apps/console/Dockerfile ships .next/standalone (M5)
  poweredByHeader: false,
  eslint: { ignoreDuringBuilds: true }, // `npm run lint` runs ESLint explicitly in `check`
  typescript: { ignoreBuildErrors: false },
};

export default nextConfig;
