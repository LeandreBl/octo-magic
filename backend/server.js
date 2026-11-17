// Online server: Firebase login, player profiles and spells (Postgres), the
// forge behind a login, the web build of the game and the coop lobby. Coop
// games run peer to peer over WebRTC: the lobby only introduces the players
// (signaling), the TURN server of docker-compose.yml relays when they cannot
// reach each other directly.
//
// HTTP (Authorization: Bearer <Firebase ID token> on /api):
//   GET  /health
//   GET  /api/config             -> {firebaseApiKey} for the game (no login)
//   GET  /api/profile            -> the saved profile ({} for a new player)
//   PUT  /api/profile            <- the profile (JSON object, Profile.save())
//   GET  /api/spells/<id>        -> a .spell bundle (zip) of the player
//   PUT  /api/spells/<id>        <- a .spell bundle
//   POST /api/forge, GET /api/forge/<job>   proxied to the forge (server/forge.py)
//   GET  /terms, /privacy        legal pages (legal/*.html), linked from Google sign-in
//   GET  /...                    the web export of the game
//
// WebSocket /play, JSON text messages. The host is peer 1, players 2, 3...;
// a player talks to the host only (the host's game relays between players).
//   -> {"op": "host", "token": T}           open a room
//   <- {"op": "hosted", "code": "K7QX", "id": 1, "ice": [RTCIceServer...]}
//   -> {"op": "join", "code": "K7QX", "token": T}
//   <- {"op": "joined", "id": 2, "ice": [...]}
//   <- {"op": "peer", "id": 2}              to the host: a player joined
//   <- {"op": "left", "id": 2}              to the host: a player left
//   -> {"op": "signal", "to": 1, "data": D} WebRTC offer/answer/candidate
//   <- {"op": "signal", "from": 2, "data": D}
//   <- {"op": "error", "msg": "..."}        then the socket closes
// The room dies with its host.

import http from "node:http";
import { createHmac, randomInt } from "node:crypto";
import { WebSocketServer } from "ws";
import { readFile } from "node:fs/promises";
import path from "node:path";

const MAX_JSON = 512 * 1024;
const MAX_BUNDLE = 4 * 1024 * 1024;
const SPELL_ID = /^[\w-]{1,64}$/;
const MAX_SIGNAL = 64 * 1024;
const MAX_PLAYERS = 4;
const MAX_ROOMS = 1000;
const HELLO_TIMEOUT = 10_000;
const PING_EVERY = 20_000; // keeps proxies from closing quiet lobbies
const CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I/L
const TURN_TTL = 12 * 3600; // seconds
const LEGAL = new URL("legal/", import.meta.url);
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
 * forgeEmails: the only accounts allowed to forge, by email (null: every logged-in player).
 * config: public settings the game reads before logging in.
 * turn: {url, secret} of the TURN server (coturn --use-auth-secret), or null.
 */
export function createServer({ verify, store, forgeUrl = null, forgeEmails = null, webDir = null, config = {}, turn = null }) {
  async function user(req) {
    const m = /^Bearer (.+)$/.exec(req.headers.authorization ?? "");
    if (!m) throw new HttpError(401, "missing token");
    try { return await verify(m[1]); } catch { throw new HttpError(401, "invalid token"); }
  }

  async function api(req, res, url) {
    const { uid, email } = await user(req);
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
      if (forgeEmails && !forgeEmails.includes(String(email).toLowerCase())) throw new HttpError(403, "forge not open to this account");
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
      if (url.pathname === "/terms" || url.pathname === "/privacy") {
        return send(res, 200, await readFile(new URL(url.pathname.slice(1) + ".html", LEGAL)), "text/html; charset=utf-8");
      }
      if (req.method === "GET") return await staticFile(res, url);
      throw new HttpError(404, "not found");
    } catch (e) {
      if (!(e instanceof HttpError)) console.error(e);
      if (!res.headersSent) send(res, e.code ?? 500, { error: e instanceof HttpError ? e.message : "server error" });
    }
  });

  lobby(server, verify, turn);
  return server;
}

/** RTCIceServer list for one player: public STUN, and TURN with time-limited
 * credentials (coturn's TURN REST API scheme). */
export function iceServers(uid, turn, now = Date.now() / 1000) {
  const ice = [{ urls: ["stun:stun.l.google.com:19302"] }];
  if (turn?.url && turn?.secret) {
    const username = `${Math.floor(now) + TURN_TTL}:${uid}`;
    ice.push({ urls: [turn.url], username, credential: createHmac("sha1", turn.secret).update(username).digest("base64") });
  }
  return ice;
}

/** The coop lobby on /play: rooms with a short code, WebRTC signaling. */
function lobby(server, verify, turn) {
  const wss = new WebSocketServer({ server, path: "/play", maxPayload: MAX_SIGNAL });
  const rooms = new Map(); // code -> Map(id -> ws)
  const send = (ws, msg) => ws.readyState === ws.OPEN && ws.send(JSON.stringify(msg));
  const fail = (ws, msg) => { send(ws, { op: "error", msg }); ws.close(); };

  setInterval(() => wss.clients.forEach((ws) => ws.ping()), PING_EVERY).unref();

  wss.on("connection", (ws) => {
    let room = null, id = 0, greeted = false;
    const hello = setTimeout(() => fail(ws, "no hello"), HELLO_TIMEOUT);
    ws.on("error", () => {});
    ws.on("message", async (raw, binary) => {
      let msg;
      try { msg = JSON.parse(raw); } catch { msg = null; }
      if (binary || !msg || typeof msg !== "object") return fail(ws, "bad message");
      if (msg.op === "signal" && room) {
        const to = room.get(msg.to);
        // A player reaches the host only; the host reaches its players.
        if (to && to !== ws && (id === 1 || msg.to === 1)) send(to, { op: "signal", from: id, data: msg.data });
        return;
      }
      if (greeted || (msg.op !== "host" && msg.op !== "join")) return fail(ws, "bad message");
      greeted = true;
      clearTimeout(hello);
      let uid;
      try { ({ uid } = await verify(String(msg.token ?? ""))); } catch { return fail(ws, "invalid token"); }
      if (ws.readyState !== ws.OPEN) return;
      if (msg.op === "host") {
        if (rooms.size >= MAX_ROOMS) return fail(ws, "server full");
        let code;
        do code = Array.from({ length: 4 }, () => CODE_CHARS[randomInt(CODE_CHARS.length)]).join("");
        while (rooms.has(code));
        room = new Map([[1, ws]]);
        rooms.set(code, room);
        id = 1;
        ws.on("close", () => {
          rooms.delete(code);
          for (const [pid, p] of room) if (pid !== 1) fail(p, "host left");
        });
        return send(ws, { op: "hosted", code, id, ice: iceServers(uid, turn) });
      }
      const r = rooms.get(String(msg.code ?? "").toUpperCase());
      if (!r) return fail(ws, "no such room");
      if (r.size >= MAX_PLAYERS) return fail(ws, "room full");
      room = r;
      id = 2;
      while (room.has(id)) id++;
      room.set(id, ws);
      ws.on("close", () => {
        if (room.get(id) !== ws) return;
        room.delete(id);
        send(room.get(1), { op: "left", id });
      });
      send(ws, { op: "joined", id, ice: iceServers(uid, turn) });
      send(room.get(1), { op: "peer", id });
    });
  });
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
    // Set while the forge runs on the owner's Claude account (no API key).
    forgeEmails: process.env.FORGE_EMAILS ? process.env.FORGE_EMAILS.toLowerCase().split(",").map((s) => s.trim()) : null,
    webDir: process.env.WEB_DIR || null,
    // The Firebase web API key is public (it ships in every client).
    config: { firebaseApiKey: process.env.FIREBASE_API_KEY ?? "" },
    turn: { url: process.env.TURN_URL, secret: process.env.TURN_SECRET },
  }).listen(port, () => console.log(`octo-magic server on :${port}`));
}
