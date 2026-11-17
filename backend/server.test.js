import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHmac } from "node:crypto";
import { createServer, iceServers } from "./server.js";

// Tokens are "token-<uid>"; profiles and spells live in Maps.
const verify = async (t) => { if (!t.startsWith("token-")) throw new Error("bad"); return { uid: t.slice(6) }; };
const profiles = new Map(), spells = new Map();
const store = {
  getProfile: async (uid) => profiles.get(uid),
  putProfile: async (uid, p) => { profiles.set(uid, p); },
  getSpell: async (uid, id) => spells.get(uid + "/" + id),
  putSpell: async (uid, id, b) => { spells.set(uid + "/" + id, b); },
};

const server = createServer({ verify, store, config: { firebaseApiKey: "k" } });
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}`;
test.after(() => server.close());

const api = (p, uid, init = {}) => fetch(base + p, { ...init, headers: uid ? { Authorization: `Bearer token-${uid}` } : {} });

test("profile and spells are kept per player", async () => {
  assert.equal((await api("/api/profile")).status, 401);
  assert.equal((await api("/api/profile", null, { headers: { Authorization: "Bearer nope" } })).status, 401);
  assert.deepEqual(await (await api("/api/profile", "ann")).json(), {});
  assert.equal((await api("/api/profile", "ann", { method: "PUT", body: '{"gold": 42}' })).status, 200);
  assert.deepEqual(await (await api("/api/profile", "ann")).json(), { gold: 42 });
  assert.deepEqual(await (await api("/api/profile", "bob")).json(), {});
  assert.equal((await api("/api/profile", "ann", { method: "PUT", body: "[1]" })).status, 400);
  assert.equal((await api("/api/profile", "ann", { method: "PUT", body: "{" })).status, 400);

  assert.equal((await api("/api/spells/s1", "ann", { method: "PUT", body: "nope" })).status, 400);
  assert.equal((await api("/api/spells/s1", "ann", { method: "PUT", body: "PK\x03\x04zip" })).status, 200);
  assert.equal(await (await api("/api/spells/s1", "ann")).text(), "PK\x03\x04zip");
  assert.equal((await api("/api/spells/s1", "bob")).status, 404);
  assert.equal((await api("/api/spells/..%2Fx", "ann")).status, 400);
});

test("config is public", async () => {
  assert.deepEqual(await (await api("/api/config")).json(), { firebaseApiKey: "k" });
});

// A lobby client: messages are queued, next() waits for one.
async function player(hello) {
  const ws = new WebSocket(base.replace("http", "ws") + "/play");
  const queue = [], waiting = [];
  ws.onmessage = (e) => { const m = JSON.parse(e.data); waiting.length ? waiting.shift()(m) : queue.push(m); };
  ws.onclose = () => { const m = { op: "closed" }; waiting.length ? waiting.shift()(m) : queue.push(m); };
  await new Promise((r) => { ws.onopen = r; });
  ws.next = () => queue.length ? queue.shift() : new Promise((r) => waiting.push(r));
  ws.json = (m) => ws.send(JSON.stringify(m));
  if (hello) ws.json(hello);
  return ws;
}

test("lobby: rooms, signaling between host and players", async () => {
  const host = await player({ op: "host", token: "token-ann" });
  const hosted = await host.next();
  assert.equal(hosted.op, "hosted");
  assert.match(hosted.code, /^[A-Z2-9]{4}$/);
  assert.equal(hosted.ice[0].urls[0], "stun:stun.l.google.com:19302");

  const a = await player({ op: "join", code: hosted.code.toLowerCase(), token: "token-bob" });
  assert.equal((await a.next()).id, 2);
  assert.deepEqual(await host.next(), { op: "peer", id: 2 });
  const b = await player({ op: "join", code: hosted.code, token: "token-cy" });
  assert.equal((await b.next()).id, 3);
  assert.deepEqual(await host.next(), { op: "peer", id: 3 });

  host.json({ op: "signal", to: 2, data: { sdp: "offer" } });
  assert.deepEqual(await a.next(), { op: "signal", from: 1, data: { sdp: "offer" } });
  a.json({ op: "signal", to: 3, data: "sneaky" }); // players reach the host only
  a.json({ op: "signal", to: 1, data: { sdp: "answer" } });
  assert.deepEqual(await host.next(), { op: "signal", from: 2, data: { sdp: "answer" } });

  a.close();
  assert.deepEqual(await host.next(), { op: "left", id: 2 });
  host.close();
  assert.deepEqual(await b.next(), { op: "error", msg: "host left" });
  assert.equal((await b.next()).op, "closed");
});

test("lobby: bad token, unknown room, full room", async () => {
  const bad = await player({ op: "host", token: "nope" });
  assert.deepEqual(await bad.next(), { op: "error", msg: "invalid token" });
  const lost = await player({ op: "join", code: "ZZZZ", token: "token-x" });
  assert.deepEqual(await lost.next(), { op: "error", msg: "no such room" });
  const host = await player({ op: "host", token: "token-h" });
  const { code } = await host.next();
  for (let i = 0; i < 3; i++) assert.equal((await (await player({ op: "join", code, token: "token-p" })).next()).op, "joined");
  assert.deepEqual(await (await player({ op: "join", code, token: "token-p" })).next(), { op: "error", msg: "room full" });
  host.close();
});

test("TURN credentials are coturn's REST scheme", () => {
  const [, turn] = iceServers("ann", { url: "turn:t.example:3478", secret: "s" }, 1000);
  assert.equal(turn.username, `${1000 + 12 * 3600}:ann`);
  assert.equal(turn.credential, createHmac("sha1", "s").update(turn.username).digest("base64"));
  assert.equal(iceServers("ann", null).length, 1);
});

// Two headless games over WebRTC through this lobby (tests/net_e2e.gd).
const godot = process.env.GODOT || "godot";
const hasGodot = spawnSync(godot, ["--version"]).status === 0;
const root = new URL("..", import.meta.url).pathname;
const game = (args) => spawn(godot, ["--headless", "--path", root, "--script", "tests/net_e2e.gd", "--", ...args],
  { env: { ...process.env, OCTO_SERVER: base } });
const finished = (p) => new Promise((resolve) => {
  let out = "";
  p.stdout.on("data", (d) => { out += d; });
  p.stderr.on("data", (d) => { out += d; });
  p.on("close", () => resolve(out));
});

test("solo is a host alone", { skip: !hasGodot, timeout: 60_000 }, async () => {
  const out = await finished(game(["solo"]));
  assert.match(out, /E2E OK/, out);
  assert.doesNotMatch(out, /ERROR/, out);
});

test("two headless games over WebRTC", { skip: !hasGodot, timeout: 90_000 }, async () => {
  const host = game(["host"]);
  const hostOut = finished(host);
  const code = await new Promise((resolve, reject) => {
    host.stdout.on("data", (d) => { const m = /CODE (\w+)/.exec(d); if (m) resolve(m[1]); });
    host.on("close", () => reject(new Error("host got no room code")));
  });
  const joinOut = await finished(game(["join", code]));
  assert.match(joinOut, /E2E OK/, joinOut);
  assert.doesNotMatch(joinOut, /ERROR/, joinOut);
  const out = await hostOut;
  assert.match(out, /E2E OK/, out);
  assert.doesNotMatch(out, /ERROR/, out);
});
