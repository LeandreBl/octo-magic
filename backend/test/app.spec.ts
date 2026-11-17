import "./env";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHmac } from "node:crypto";
import type { AddressInfo } from "node:net";
import path from "node:path";
import { after, before, test } from "node:test";
import { Test } from "@nestjs/testing";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { AppModule } from "../src/app.module";
import { setupApp } from "../src/app.setup";
import { FirebaseService } from "../src/auth/firebase.service";
import { iceServers } from "../src/lobby/ice";
import { PrismaService } from "../src/prisma/prisma.service";

// Tokens are "token-<uid>"; characters and spells live in Maps.
const firebase = {
  verifyToken: async (t: string) => {
    if (!t.startsWith("token-")) throw new Error("bad token");
    return { uid: t.slice(6), email: `${t.slice(6)}@x.org` };
  },
};
type Where = { where: { uid?: string; id?: string; uid_id?: { uid: string; id: string } } };
type Row = { id: string; uid: string; name: string; spell: string; profile: unknown; updatedAt: Date };
const characters: Row[] = [];
const spells = new Map<string, Uint8Array>();
const key = ({ where }: Where) => `${where.uid_id!.uid}/${where.uid_id!.id}`;
const mine = ({ where }: Where) =>
  characters.filter((c) => c.uid === where.uid && (where.id === undefined || c.id === where.id));
const pick = ({ id, name, spell, updatedAt }: Row) => ({ id, name, spell, updatedAt });
const drop = (q: Where) => {
  const gone = mine(q);
  gone.forEach((c) => characters.splice(characters.indexOf(c), 1));
  return { count: gone.length };
};
const prisma = {
  character: {
    findMany: async (q: Where) => mine(q).map(pick),
    findFirst: async (q: Where) => mine(q)[0] ?? null,
    count: async (q: Where) => mine(q).length,
    create: async ({ data }: { data: Omit<Row, "id" | "updatedAt"> }) => {
      const c = { ...data, id: `c${characters.length + 1}-${data.uid}`, updatedAt: new Date() };
      characters.push(c);
      return pick(c);
    },
    updateMany: async (q: Where & { data: { profile: unknown } }) => {
      mine(q).forEach((c) => (c.profile = q.data.profile));
      return { count: mine(q).length };
    },
    deleteMany: async (q: Where) => drop(q),
  },
  spell: {
    findUnique: async (q: Where) => (spells.has(key(q)) ? { bundle: spells.get(key(q)) } : null),
    upsert: async (q: Where & { create: { bundle: Uint8Array } }) => spells.set(key(q), q.create.bundle),
    deleteMany: async ({ where }: Where) => [...spells.keys()].forEach((k) => k.startsWith(`${where.uid}/`) && spells.delete(k)),
  },
  $transaction: (ops: Promise<unknown>[]) => Promise.all(ops),
};

async function start(): Promise<[NestExpressApplication, string]> {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(FirebaseService)
    .useValue(firebase)
    .overrideProvider(PrismaService)
    .useValue(prisma)
    .compile();
  const app = moduleRef.createNestApplication<NestExpressApplication>({ bodyParser: false, logger: false });
  setupApp(app);
  await app.listen(0, "127.0.0.1");
  return [app, `http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}`];
}

let app: NestExpressApplication;
let base = "";

before(async () => {
  [app, base] = await start();
});
after(() => app.close());

const api = (p: string, uid: string | null, init: RequestInit = {}) =>
  fetch(base + p, { ...init, headers: uid ? { Authorization: `Bearer token-${uid}` } : init.headers });

const post = (uid: string, body: unknown) =>
  api("/api/characters", uid, { method: "POST", body: JSON.stringify(body) });

test("characters, their profiles and spells are kept per player", async () => {
  assert.equal((await api("/api/characters", null)).status, 401);
  const bad = await api("/api/characters", null, { headers: { Authorization: "Bearer nope" } });
  assert.equal(bad.status, 401);
  assert.deepEqual(await bad.json(), { error: "invalid token" });
  assert.deepEqual(await (await api("/api/characters", "ann")).json(), []);

  const made = await post("ann", { name: " Zed ", spell: "fireball", profile: { gold: 42 } });
  assert.equal(made.status, 201);
  const zed = await made.json();
  assert.equal(zed.name, "Zed");
  assert.equal(zed.spell, "fireball");
  const kim = await (await post("ann", { name: "Kim", spell: "frost" })).json();
  const list = await (await api("/api/characters", "ann")).json();
  assert.deepEqual(list.map((c: { name: string }) => c.name), ["Zed", "Kim"]);
  for (const body of [{ spell: "x" }, { name: "a".repeat(25), spell: "x" }, { name: "a", spell: "../x" },
    { name: "a", spell: "x", profile: [1] }, [1]]) {
    assert.equal((await post("ann", body)).status, 400, JSON.stringify(body));
  }

  const profile = (uid: string, id: string, init?: RequestInit) => api(`/api/characters/${id}/profile`, uid, init);
  assert.deepEqual(await (await profile("ann", zed.id)).json(), { gold: 42 });
  assert.deepEqual(await (await profile("ann", kim.id)).json(), {});
  assert.equal((await profile("ann", kim.id, { method: "PUT", body: '{"gold": 7}' })).status, 200);
  assert.deepEqual(await (await profile("ann", kim.id)).json(), { gold: 7 });
  assert.deepEqual(await (await profile("ann", zed.id)).json(), { gold: 42 });
  assert.equal((await profile("bob", zed.id)).status, 404);
  assert.equal((await profile("bob", zed.id, { method: "PUT", body: "{}" })).status, 404);
  assert.equal((await api(`/api/characters/${zed.id}`, "bob", { method: "DELETE" })).status, 404);
  assert.equal((await profile("ann", zed.id, { method: "PUT", body: "[1]" })).status, 400);
  assert.equal((await profile("ann", zed.id, { method: "PUT", body: "{" })).status, 400);
  const big = await profile("ann", zed.id, { method: "PUT", body: `{"x": "${"a".repeat(600_000)}"}` });
  assert.equal(big.status, 413);

  assert.equal((await api(`/api/characters/${kim.id}`, "ann", { method: "DELETE" })).status, 200);
  assert.equal((await profile("ann", kim.id)).status, 404);
  for (let i = 1; i < 10; i++) assert.equal((await post("bob", { name: `b${i}`, spell: "x" })).status, 201);
  assert.equal((await post("bob", { name: "b10", spell: "x" })).status, 201);
  assert.equal((await post("bob", { name: "b11", spell: "x" })).status, 400);

  assert.equal((await api("/api/spells/s1", "ann", { method: "PUT", body: "nope" })).status, 400);
  assert.equal((await api("/api/spells/s1", "ann", { method: "PUT", body: "PK\x03\x04zip" })).status, 200);
  const got = await api("/api/spells/s1", "ann");
  assert.equal(got.headers.get("content-type"), "application/zip");
  assert.equal(await got.text(), "PK\x03\x04zip");
  assert.equal((await api("/api/spells/s1", "bob")).status, 404);
  assert.equal((await api("/api/spells/..%2Fx", "ann")).status, 400);

  assert.equal((await api("/api/account", null, { method: "DELETE" })).status, 401);
  assert.equal((await api("/api/account", "ann", { method: "DELETE" })).status, 200);
  assert.deepEqual(await (await api("/api/characters", "ann")).json(), []);
  assert.equal((await profile("ann", zed.id)).status, 404);
  assert.equal((await api("/api/spells/s1", "ann")).status, 404);
});

test("website pages are public", async () => {
  for (const p of ["/", "/account", "/game", "/terms", "/privacy"]) {
    const r = await api(p, null);
    assert.equal(r.status, 200);
    assert.match(r.headers.get("content-type") ?? "", /text\/html/);
    assert.match(await r.text(), /<h1>/);
  }
});

test("config and health are public", async () => {
  assert.deepEqual(await (await api("/api/config", null)).json(), { firebaseApiKey: "k" });
  assert.deepEqual(await (await api("/health", null)).json(), { ok: true });
});

test("no forge configured: 404 behind the login", async () => {
  assert.equal((await api("/api/forge", null, { method: "POST" })).status, 401);
  assert.equal((await api("/api/forge", "ann", { method: "POST", body: "{}" })).status, 404);
});

test("forge is limited to FORGE_EMAILS", async () => {
  process.env.FORGE_URL = "http://127.0.0.1:1";
  process.env.FORGE_EMAILS = "Ann@x.org";
  const [forge, url] = await start();
  delete process.env.FORGE_URL;
  delete process.env.FORGE_EMAILS;
  const get = (uid: string) => fetch(`${url}/api/forge/x`, { headers: { Authorization: `Bearer token-${uid}` } });
  assert.equal((await get("bob")).status, 403);
  assert.equal((await get("ann")).status, 502); // allowed, the forge is down
  await forge.close();
});

type Player = WebSocket & { next(): Promise<any>; json(m: unknown): void };

// A lobby client: messages are queued, next() waits for one.
async function player(hello?: unknown): Promise<Player> {
  const ws = new WebSocket(base.replace("http", "ws") + "/play") as Player;
  const queue: unknown[] = [];
  const waiting: ((m: unknown) => void)[] = [];
  const push = (m: unknown) => (waiting.length ? waiting.shift()!(m) : queue.push(m));
  ws.onmessage = (e) => push(JSON.parse(e.data));
  ws.onclose = () => push({ op: "closed" });
  await new Promise((r) => (ws.onopen = r));
  ws.next = () => (queue.length ? Promise.resolve(queue.shift()) : new Promise((r) => waiting.push(r)));
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
  for (let i = 0; i < 7; i++) {
    assert.equal((await (await player({ op: "join", code, token: "token-p" })).next()).op, "joined");
  }
  assert.deepEqual(await (await player({ op: "join", code, token: "token-p" })).next(), {
    op: "error",
    msg: "room full",
  });
  host.close();
});

test("TURN credentials are coturn's REST scheme", () => {
  const [, turn] = iceServers("ann", { url: "turn:t.example:3478", secret: "s" }, 1000);
  assert.equal(turn.username, `${1000 + 12 * 3600}:ann`);
  assert.equal(turn.credential, createHmac("sha1", "s").update(turn.username!).digest("base64"));
  assert.equal(iceServers("ann").length, 1);
});

// Two headless games over WebRTC through this lobby (tests/net_e2e.gd).
const godot = process.env.GODOT || "godot";
const hasGodot = spawnSync(godot, ["--version"]).status === 0;
const root = path.resolve(__dirname, "../..");
const game = (args: string[]) =>
  spawn(godot, ["--headless", "--path", root, "--script", "tests/net_e2e.gd", "--", ...args], {
    env: { ...process.env, OCTO_SERVER: base },
  });
const finished = (p: ReturnType<typeof game>) =>
  new Promise<string>((resolve) => {
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (out += d));
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
  const code = await new Promise<string>((resolve, reject) => {
    host.stdout.on("data", (d) => {
      const m = /CODE (\w+)/.exec(String(d));
      if (m) resolve(m[1]);
    });
    host.on("close", () => reject(new Error("host got no room code")));
  });
  const joinOut = await finished(game(["join", code]));
  assert.match(joinOut, /E2E OK/, joinOut);
  assert.doesNotMatch(joinOut, /ERROR/, joinOut);
  const out = await hostOut;
  assert.match(out, /E2E OK/, out);
  assert.doesNotMatch(out, /ERROR/, out);
});
