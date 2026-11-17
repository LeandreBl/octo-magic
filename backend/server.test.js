import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

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
