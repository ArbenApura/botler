# THE SERVER IMAGE: THE APP BUILT FOR NODE, ITS PRODUCTION DEPENDENCIES, THE MIGRATIONS AND THE MIGRATE COMMAND
# Build from the server/ folder:   docker build -t botler-server .
# It listens on port 3000. deploy/vps/docker-compose.yml runs it with PostgreSQL and a one shot migration step.

FROM node:24-slim AS build
ENV CI=1
# The host has 3.7 GB shared with AFB, so the build may not take more than about a gigabyte of heap
ENV NODE_OPTIONS=--max-old-space-size=1024
RUN corepack enable
WORKDIR /app
# The manifests first, so the install is cached until a dependency changes
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn/releases .yarn/releases
RUN yarn install --immutable
COPY . .
# The build checks the environment variables, so it gets placeholders. They stay in this stage and are never part of the image
RUN BOTLER_BASE_URL=https://build.invalid BETTER_AUTH_SECRET=build-time-placeholder-0123456789abcdef \
    GOOGLE_CLIENT_ID=build GOOGLE_CLIENT_SECRET=build ALLOWED_EMAILS=build@build.invalid \
    MODEL_PROVIDER=deepseek DEEPSEEK_API_KEY=build \
    yarn run build && yarn run build:cli

FROM node:24-slim AS deps
ENV CI=1
RUN corepack enable
WORKDIR /app
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn/releases .yarn/releases
# Only the production dependencies: no test tools, no linters
RUN yarn workspaces focus --production
# The embedding runtime ships binaries for every system. Only Linux is needed here, which saves about 220 MB
RUN rm -rf node_modules/onnxruntime-node/bin/napi-v6/darwin node_modules/onnxruntime-node/bin/napi-v6/win32

FROM node:24-slim
ENV NODE_ENV=production PORT=3000 HOST=0.0.0.0
# A chat message may carry pictures (about 9.5 MB at most). The route itself still reads only 64 KB unless it asks for more (readJson)
ENV BODY_SIZE_LIMIT=10485760
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./package.json
COPY --from=build /app/build ./build
COPY --from=build /app/cli ./cli
COPY src/lib/server/db/migrations ./src/lib/server/db/migrations
# Where the embedding model is kept after its first download (a volume in compose, so it survives a rebuild)
RUN mkdir /models && chown node:node /models
ENV BOTLER_EMBED_CACHE=/models
USER node
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=4s --start-period=20s --retries=4 \
  CMD node -e "fetch('http://127.0.0.1:3000/healthz').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "build/index.js"]
