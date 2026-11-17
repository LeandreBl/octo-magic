-- Several characters per account: each player's profile becomes their first
-- character, named "Mage", with the spell it had equipped.
CREATE TABLE "characters" (
    "id" TEXT NOT NULL,
    "uid" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "spell" TEXT NOT NULL,
    "profile" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "characters_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "characters_uid_idx" ON "characters"("uid");

INSERT INTO "characters" ("id", "uid", "name", "spell", "profile", "updated_at")
SELECT gen_random_uuid()::text, "uid", 'Mage',
       COALESCE("profile"->'spells'->>'primary', 'fireball'), "profile", "updated_at"
FROM "players";

DROP TABLE "players";
