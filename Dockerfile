# Proxima — headless Electron hub sized for ~512MB VPS
# Build from the REPO ROOT (folder that contains electron/, src/, package.json):
#   docker build -t proxima .
#   docker compose up -d --build
#
# Run:
#   docker run --rm -p 3210:3210 --memory=512m --memory-swap=1g --shm-size=256m \
#     -e PROXIMA_API_KEY=sk-... \
#     -e PROXIMA_PROVIDER=chatgpt \
#     -e PROXIMA_COOKIES_CHATGPT='[...]' \
#     -v proxima-data:/data proxima

FROM node:20-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    ELECTRON_SKIP_BINARY_DOWNLOAD=0 \
    PROXIMA_SERVER=1 \
    PROXIMA_LOW_MEMORY=1 \
    PROXIMA_SKIP_PYTHON=1 \
    PROXIMA_SKIP_MCP=1 \
    PROXIMA_HOST=0.0.0.0 \
    PROXIMA_REST_PORT=3210 \
    PROXIMA_DATA_DIR=/data \
    PROXIMA_PROVIDER=chatgpt \
    NODE_OPTIONS=--max-old-space-size=128

# Chromium/Electron runtime deps + tiny virtual display + native module build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libxshmfence1 \
    libxss1 \
    libxtst6 \
    python3 \
    make \
    g++ \
    xdg-utils \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
# Production deps + Electron (devDependency) for the container runtime
RUN npm ci --ignore-scripts \
    && npm install electron@33.4.11 --no-save \
    && npm rebuild better-sqlite3 --build-from-source || true \
    && npm cache clean --force \
    && apt-get purge -y python3 make g++ \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Full app sources — build context MUST be the Proxima repo root
COPY electron ./electron
COPY src ./src
COPY cli ./cli
COPY assets ./assets
COPY sdk ./sdk
COPY docs/openapi.json ./docs/openapi.json

# Fail early with a clear message if the context was incomplete (Coolify/base-dir mistakes)
RUN set -eu; \
    for p in electron/main-v2.cjs src/mcp/index.js cli/proxima-cli.cjs docs/openapi.json node_modules/electron; do \
      if [ ! -e "$p" ]; then \
        echo "ERROR: missing $p — Docker build context is not the Proxima repo root."; \
        echo "Set the build context / base directory to the folder that contains electron/, src/, package.json."; \
        ls -la; \
        exit 1; \
      fi; \
    done

# Entrypoint inlined (no dependency on scripts/ in the build context)
RUN printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'export PROXIMA_SERVER="${PROXIMA_SERVER:-1}"' \
  'export PROXIMA_LOW_MEMORY="${PROXIMA_LOW_MEMORY:-1}"' \
  'export PROXIMA_SKIP_PYTHON="${PROXIMA_SKIP_PYTHON:-1}"' \
  'export PROXIMA_SKIP_MCP="${PROXIMA_SKIP_MCP:-1}"' \
  'export PROXIMA_PROVIDER="${PROXIMA_PROVIDER:-chatgpt}"' \
  'export PROXIMA_HOST="${PROXIMA_HOST:-0.0.0.0}"' \
  'export PROXIMA_REST_PORT="${PROXIMA_REST_PORT:-3210}"' \
  'export PROXIMA_DATA_DIR="${PROXIMA_DATA_DIR:-/data}"' \
  'export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-x11}"' \
  'export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=128}"' \
  'mkdir -p "$PROXIMA_DATA_DIR"' \
  'if [ -z "${DISPLAY:-}" ]; then' \
  '  export DISPLAY=:99' \
  '  Xvfb :99 -screen 0 1024x768x24 -ac -nolisten tcp -dpi 96 >/tmp/xvfb.log 2>&1 &' \
  '  XVFB_PID=$!' \
  '  trap "kill $XVFB_PID 2>/dev/null || true" EXIT INT TERM' \
  '  i=0' \
  '  while [ ! -e /tmp/.X11-unix/X99 ] && [ "$i" -lt 50 ]; do i=$((i + 1)); sleep 0.1; done' \
  'fi' \
  'echo "[entrypoint] REST http://${PROXIMA_HOST}:${PROXIMA_REST_PORT} provider=${PROXIMA_PROVIDERS:-$PROXIMA_PROVIDER} docs=/ swagger=/swagger"' \
  'cd /app' \
  'exec ./node_modules/.bin/electron . --headless --server --no-sandbox "$@"' \
  > /usr/local/bin/proxima-entrypoint \
  && chmod +x /usr/local/bin/proxima-entrypoint \
  && mkdir -p /data \
  && chown -R node:node /app /data

USER node
EXPOSE 3210
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PROXIMA_REST_PORT||3210)+'/openapi.json',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

ENTRYPOINT ["proxima-entrypoint"]
