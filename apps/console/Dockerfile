# FarmerApp console image (Next.js standalone server on :3000, non-root).
# Build context: the repository root, because `prebuild` regenerates app/tokens.css from
# design/tokens.json. apps/console/Dockerfile.dockerignore (BuildKit per-Dockerfile ignore
# file) scopes the context to apps/console + design/tokens.json; the root .dockerignore used
# by the api / worker / jobs images is not affected.
#   docker build -f apps/console/Dockerfile --build-arg NEXT_PUBLIC_API_URL=https://api.dev.farmerapp.in .
#
# NEXT_PUBLIC_* values are inlined into the browser bundle at build time, so the image is
# per environment: deploy.yml passes the env's API URL. Leaving it empty builds the in-app
# mock API (/api/mock), which is what the local smoke test uses.

FROM node:22-slim AS deps
WORKDIR /repo/apps/console
COPY apps/console/package.json apps/console/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund

FROM node:22-slim AS build
ARG NEXT_PUBLIC_API_URL=""
ARG NEXT_PUBLIC_MAP_TILE_URL=""
ENV NEXT_TELEMETRY_DISABLED=1 \
    NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL} \
    NEXT_PUBLIC_MAP_TILE_URL=${NEXT_PUBLIC_MAP_TILE_URL}
WORKDIR /repo
COPY design/tokens.json design/tokens.json
COPY apps/console apps/console
COPY --from=deps /repo/apps/console/node_modules apps/console/node_modules
WORKDIR /repo/apps/console
# `npm run build` = prebuild (tokens) + next build (output: "standalone").
RUN npm run build

FROM node:22-slim AS runtime
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
WORKDIR /app
RUN groupadd --system app && useradd --system --gid app --uid 10001 --no-create-home app
COPY --from=build --chown=app:app /repo/apps/console/.next/standalone ./
COPY --from=build --chown=app:app /repo/apps/console/.next/static ./.next/static
USER app
EXPOSE 3000
CMD ["node", "server.js"]
