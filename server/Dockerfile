# Build context: the repository root (the forge reads docs/ and spell/).
FROM python:3.13-slim
# Claude Code, for the forge without ANTHROPIC_API_KEY: it then runs
# `claude -p` on a Claude subscription (CLAUDE_CODE_OAUTH_TOKEN).
RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && npm install -g --no-audit --no-fund @anthropic-ai/claude-code \
    && npm cache clean --force && apt-get purge -y npm && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY docs docs
COPY spell spell
COPY server server
# Forged bundles, kept on the forge_cache volume (docker-compose.yml).
RUN mkdir /cache && chown nobody /cache
ENV FORGE_CACHE=/cache
USER nobody
# Claude Code writes its config under $HOME.
ENV HOME=/tmp
EXPOSE 8765
CMD ["python3", "server/forge.py"]
