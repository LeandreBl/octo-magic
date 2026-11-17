// Online server: Firebase login, player profiles and spells (Postgres), the
// forge behind a login and the web build of the game. Multiplayer goes through
// the coop relay (relay/relay.py), its own container in docker-compose.yml.
//
// HTTP (Authorization: Bearer <Firebase ID token> on /api):
//   GET  /health
//   GET  /api/config             -> {firebaseApiKey, relayUrl} for the game (no login)
//   GET  /api/profile            -> the saved profile ({} for a new player)
//   PUT  /api/profile            <- the profile (JSON object, Profile.save())
//   GET  /api/spells/<id>        -> a .spell bundle (zip) of the player
//   PUT  /api/spells/<id>        <- a .spell bundle
//   POST /api/forge, GET /api/forge/<job>   proxied to the forge (server/forge.py)
//   GET  /...                    the web export of the game

import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";

const MAX_JSON = 512 * 1024;
const MAX_BUNDLE = 4 * 1024 * 1024;
const SPELL_ID = /^[\w-]{1,64}$/;
const MIME = {
  ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".svg": "image/svg+xml",
  ".ico": "image/x-icon", ".json": "application/json",
};

class HttpError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > limit) { reject(new HttpError(413, "body too large")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function send(res, code, body, type = "application/json") {
  const data = Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(code, { "Content-Type": type, "Access-Control-Allow-Origin": "*" });
  res.end(data);
}

/**
 * verify(token) -> {uid} or throws; store: getProfile/putProfile/getSpell/putSpell.
 * forgeUrl: base URL of the forge (null: no forge); webDir: the game's web export.
 * config: public settings the game reads before logging in.
 */
export function createServer({ verify, store, forgeUrl = null, webDir = null, config = {} }) {
  async function user(req) {
    const m = /^Bearer (.+)$/.exec(req.headers.authorization ?? "");
    if (!m) throw new HttpError(401, "missing token");
    try { return await verify(m[1]); } catch { throw new HttpError(401, "invalid token"); }
  }

  async function api(req, res, url) {
    const { uid } = await user(req);
    const p = url.pathname;
    if (p === "/api/profile" && req.method === "GET") return send(res, 200, (await store.getProfile(uid)) ?? {});
    if (p === "/api/profile" && req.method === "PUT") {
      let profile;
      try { profile = JSON.parse(await readBody(req, MAX_JSON)); } catch (e) { throw e instanceof HttpError ? e : new HttpError(400, "invalid JSON"); }
      if (!profile || typeof profile !== "object" || Array.isArray(profile)) throw new HttpError(400, "profile must be an object");
      await store.putProfile(uid, profile);
      return send(res, 200, { ok: true });
    }
    let m = /^\/api\/spells\/([^/]+)$/.exec(p);
    if (m) {
      if (!SPELL_ID.test(m[1])) throw new HttpError(400, "invalid spell id");
      if (req.method === "GET") {
        const bundle = await store.getSpell(uid, m[1]);
        return bundle ? send(res, 200, bundle, "application/zip") : send(res, 404, { error: "no such spell" });
      }
      if (req.method === "PUT") {
        const bundle = await readBody(req, MAX_BUNDLE);
        if (bundle.subarray(0, 2).toString("latin1") !== "PK") throw new HttpError(400, "not a .spell bundle");
        await store.putSpell(uid, m[1], bundle);
        return send(res, 200, { ok: true });
      }
    }
    m = /^\/api\/forge(\/[\w-]+)?$/.exec(p);
    if (m && forgeUrl) {
      const post = req.method === "POST";
      const reply = await fetch(forgeUrl + "/forge" + (m[1] ?? ""), {
        method: post ? "POST" : "GET",
        headers: { "Content-Type": "application/json" },
        body: post ? await readBody(req, MAX_JSON) : undefined,
      }).catch(() => { throw new HttpError(502, "forge unreachable"); });
      return send(res, reply.status, Buffer.from(await reply.arrayBuffer()), reply.headers.get("content-type") ?? "application/json");
    }
    throw new HttpError(404, "not found");
  }

  async function staticFile(res, url) {
    if (!webDir) throw new HttpError(404, "not found");
    const root = path.resolve(webDir);
    const file = path.resolve(root, "." + decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname));
    if (!file.startsWith(root + path.sep)) throw new HttpError(404, "not found");
    const data = await readFile(file).catch(() => { throw new HttpError(404, "not found"); });
    send(res, 200, data, MIME[path.extname(file)] ?? "application/octet-stream");
  }

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://x");
    try {
      if (req.method === "OPTIONS") {
        res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Allow-Methods": "GET, PUT, POST" });
        return res.end();
      }
      if (url.pathname === "/health") return send(res, 200, { ok: true });
      if (url.pathname === "/api/config") return send(res, 200, config);
      if (url.pathname.startsWith("/api/")) return await api(req, res, url);
      if (req.method === "GET") return await staticFile(res, url);
      throw new HttpError(404, "not found");
    } catch (e) {
      if (!(e instanceof HttpError)) console.error(e);
      if (!res.headersSent) send(res, e.code ?? 500, { error: e instanceof HttpError ? e.message : "server error" });
    }
  });

  return server;
}

// --- Production wiring: Firebase and Postgres ----------------------------------

async function postgresStore() {
  const { default: pg } = await import("pg");
  const pool = new pg.Pool(); // PGHOST, PGUSER, PGPASSWORD, PGDATABASE
  await pool.query(`
    CREATE TABLE IF NOT EXISTS players (
      uid text PRIMARY KEY,
      profile jsonb NOT NULL,
      updated_at timestamptz NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS spells (
      uid text NOT NULL,
      id text NOT NULL,
      bundle bytea NOT NULL,
      updated_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (uid, id));`);
  return {
    async getProfile(uid) {
      return (await pool.query("SELECT profile FROM players WHERE uid = $1", [uid])).rows[0]?.profile;
    },
    async putProfile(uid, profile) {
      await pool.query(`INSERT INTO players (uid, profile) VALUES ($1, $2)
        ON CONFLICT (uid) DO UPDATE SET profile = $2, updated_at = now()`, [uid, profile]);
    },
    async getSpell(uid, id) {
      return (await pool.query("SELECT bundle FROM spells WHERE uid = $1 AND id = $2", [uid, id])).rows[0]?.bundle;
    },
    async putSpell(uid, id, bundle) {
      await pool.query(`INSERT INTO spells (uid, id, bundle) VALUES ($1, $2, $3)
        ON CONFLICT (uid, id) DO UPDATE SET bundle = $3, updated_at = now()`, [uid, id, bundle]);
    },
  };
}

async function firebaseVerify() {
  const projectId = process.env.FIREBASE_PROJECT_ID;
  if (!projectId) throw new Error("FIREBASE_PROJECT_ID is required (see example.env)");
  const { initializeApp } = await import("firebase-admin/app");
  const { getAuth } = await import("firebase-admin/auth");
  // Verifying ID tokens needs only the project id (Google's public keys), no
  // service account. FIREBASE_AUTH_EMULATOR_HOST switches to the emulator.
  const auth = getAuth(initializeApp({ projectId }));
  return (token) => auth.verifyIdToken(token);
}

if (import.meta.main) {
  const port = Number(process.env.PORT ?? 8080);
  createServer({
    verify: await firebaseVerify(),
    store: await postgresStore(),
    forgeUrl: process.env.FORGE_URL || null,
    webDir: process.env.WEB_DIR || null,
    // The Firebase web API key is public (it ships in every client).
    config: { firebaseApiKey: process.env.FIREBASE_API_KEY ?? "", relayUrl: process.env.RELAY_URL || null },
  }).listen(port, () => console.log(`octo-magic server on :${port}`));
}
