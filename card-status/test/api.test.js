const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path) => { const res = await fetch(base + path, { method }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); });
test("example calls", async () => {
  const r = await call("GET", "/cards/v1/cards/4242/status"); assert.equal(r.status, 200);
  assert.ok(["ACTIVE", "BLOCKED", "EXPIRED", "PENDING_ACTIVATION"].includes(r.body.status));
  const again = await call("GET", "/cards/v1/cards/4242/status"); assert.equal(again.body.status, r.body.status);
  const bad = await call("GET", "/cards/v1/cards/42/status"); assert.equal(bad.status, 404);
});
