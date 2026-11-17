# Build context: the repository root (docker-compose.yml).
FROM python:3.13-slim
COPY relay/relay.py /app/relay.py
USER nobody
EXPOSE 8770
CMD ["python3", "/app/relay.py"]
