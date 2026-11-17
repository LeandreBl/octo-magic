#!/bin/sh
# Container entry point: applies pending migrations, then starts the API.
set -e

# Built from the POSTGRES_* parts when not given whole: the password is
# percent-encoded, so a generated one (with / + = ...) does not break the URL.
if [ -z "$DATABASE_URL" ]; then
  : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required in .env (see example.env)}"
  DATABASE_URL=$(node -e '
    const e = encodeURIComponent, v = process.env;
    process.stdout.write(
      `postgresql://${e(v.POSTGRES_USER)}:${e(v.POSTGRES_PASSWORD)}@${v.POSTGRES_HOST}:5432/${e(v.POSTGRES_DB)}`,
    );
  ')
  export DATABASE_URL
fi

# P3005: a database of the first server (backend/server.js before NestJS),
# tables there but no migration history. 0_init creates exactly those tables:
# mark it applied, then go on.
if ! out=$(npx prisma migrate deploy 2>&1); then
  echo "$out"
  echo "$out" | grep -q P3005 || exit 1
  npx prisma migrate resolve --applied 0_init
  npx prisma migrate deploy
else
  echo "$out"
fi
exec npm run "${START_SCRIPT:-start:prod}"
