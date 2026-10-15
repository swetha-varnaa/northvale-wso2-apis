const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path, body) => { const res = await fetch(base + path, { method, headers: { "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); });
test("routes", async () => {
  const r = await call("GET", "/statements/v1/accounts/ACC-5001/statements?month=2026-09"); assert.equal(r.status, 200);
  assert.equal(r.body.transactions.length, 5);
  const again = await call("GET", "/statements/v1/accounts/ACC-5001/statements?month=2026-09"); assert.deepEqual(again.body, r.body);
  const bad = await call("GET", "/statements/v1/accounts/ACC-5001/statements?month=2026-13"); assert.equal(bad.status, 400);
});
