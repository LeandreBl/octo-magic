# Build context: the repository root (docker-compose.yml).

# The web export of the game, with the Godot version of project.godot.
FROM debian:bookworm-slim AS web
ARG GODOT_VERSION=4.7.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp/godot
RUN base=https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable \
    && curl -fsSL -o godot.zip $base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && unzip -q godot.zip && mv Godot_v*_linux.x86_64 /usr/local/bin/godot \
    && curl -fsSL -o templates.tpz $base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz \
    && unzip -q templates.tpz 'templates/web_nothreads_release.zip' 'templates/version.txt' \
    && dir=/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable \
    && mkdir -p $dir && mv templates/* $dir && rm -rf /tmp/godot
WORKDIR /src
COPY . .
RUN godot --headless --import >/dev/null 2>&1 || true; \
    mkdir -p export/web && godot --headless --export-release Web export/web/index.html \
    && test -f export/web/index.pck

FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production WEB_DIR=/app/web
COPY backend/package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY backend/server.js ./
COPY --from=web /src/export/web ./web
USER node
EXPOSE 8080
CMD ["node", "server.js"]
