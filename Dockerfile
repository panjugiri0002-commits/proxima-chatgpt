# Proxima — headless Electron hub sized for ~512MB VPS
# Build:  docker build -t proxima .
# Run:    docker run --rm -p 3210:3210 --memory=512m --memory-swap=1g \
#           -e PROXIMA_API_KEY=sk-... \
#           -e PROXIMA_PROVIDER=chatgpt \
#           -e PROXIMA_COOKIES_CHATGPT_FILE=/cookies/chatgpt.json \
#           -v ./cookies:/cookies:ro -v proxima-data:/data proxima

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

COPY electron ./electron
COPY src ./src
COPY cli ./cli
COPY assets ./assets
COPY sdk ./sdk
COPY docs/openapi.json ./docs/openapi.json
COPY scripts/docker-entrypoint.sh /usr/local/bin/proxima-entrypoint

RUN sed -i 's/\r$//' /usr/local/bin/proxima-entrypoint \
    && chmod +x /usr/local/bin/proxima-entrypoint \
    && mkdir -p /data \
    && chown -R node:node /app /data

USER node
EXPOSE 3210
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PROXIMA_REST_PORT||3210)+'/openapi.json',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

ENTRYPOINT ["proxima-entrypoint"]
