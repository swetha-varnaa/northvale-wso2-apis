const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path) => { const res = await fetch(base + path, { method }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); });
test("example calls", async () => {
  const r = await call("GET", "/branches/v1/branches?city=Dubai"); assert.equal(r.status, 200); assert.equal(r.body.count, 2);
  const one = await call("GET", "/branches/v1/branches/BR-003"); assert.equal(one.body.city, "Abu Dhabi");
  const nf = await call("GET", "/branches/v1/branches/BR-999"); assert.equal(nf.status, 404);
});
