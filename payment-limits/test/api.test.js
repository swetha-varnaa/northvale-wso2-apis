const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path, body) => { const res = await fetch(base + path, { method, headers: { "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); });
test("routes", async () => {
  const r1 = await call("GET", "/payments/v1/limits/CUST-1001"); assert.equal(r1.status, 200);
  assert.equal(r1.body.dailyRemaining <= r1.body.dailyLimit, true);
  const ok = await call("POST", "/payments/v1/limits/check", { customerId: "CUST-1001", amount: 100, currency: "AED" });
  assert.equal(ok.body.decision, "ALLOW");
  const big = await call("POST", "/payments/v1/limits/check", { customerId: "CUST-1001", amount: 9999999, currency: "AED" });
  assert.equal(big.body.decision, "REVIEW");
  const bad = await call("POST", "/payments/v1/limits/check", { customerId: "CUST-1001" }); assert.equal(bad.status, 400);
});
