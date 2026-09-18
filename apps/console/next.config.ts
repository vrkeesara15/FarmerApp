import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  eslint: { ignoreDuringBuilds: true }, // `npm run lint` runs ESLint explicitly in `check`
  typescript: { ignoreBuildErrors: false },
};

export default nextConfig;
