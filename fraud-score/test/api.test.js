const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path, body) => { const res = await fetch(base + path, { method, headers: { "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); });
test("routes", async () => {
  const lo = await call("POST", "/fraud/v1/score", { transactionId: "T1", amount: 50, merchantCategory: "GROCERY", country: "AE" });
  assert.equal(lo.status, 200); assert.equal(lo.body.band, "LOW");
  const hi = await call("POST", "/fraud/v1/score", { transactionId: "T2", amount: 40000, merchantCategory: "CRYPTO", country: "RU" });
  assert.equal(hi.body.band, "HIGH");
  const again = await call("POST", "/fraud/v1/score", { transactionId: "T2", amount: 40000, merchantCategory: "CRYPTO", country: "RU" }); assert.deepEqual(again.body, hi.body);
  const bad = await call("POST", "/fraud/v1/score", { transactionId: "T2" }); assert.equal(bad.status, 400);
});
