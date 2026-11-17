# Build context: the repository root (the forge reads docs/ and spell/).
FROM python:3.13-slim
WORKDIR /app
COPY docs docs
COPY spell spell
COPY server server
USER nobody
EXPOSE 8765
CMD ["python3", "server/forge.py"]
