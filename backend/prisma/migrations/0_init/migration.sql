-- IF NOT EXISTS: a database created by the first server (backend/server.js)
-- already has these tables, and adopts this migration as is.
CREATE TABLE IF NOT EXISTS "players" (
    "uid" TEXT NOT NULL,
    "profile" JSONB NOT NULL,
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "players_pkey" PRIMARY KEY ("uid")
);

CREATE TABLE IF NOT EXISTS "spells" (
    "uid" TEXT NOT NULL,
    "id" TEXT NOT NULL,
    "bundle" BYTEA NOT NULL,
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "spells_pkey" PRIMARY KEY ("uid","id")
);
