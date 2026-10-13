const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path, body) => { const res = await fetch(base + path, { method, headers: { "Content-Type": "application/json" }, body: body === undefined ? undefined : (typeof body === "string" ? body : JSON.stringify(body)) }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); assert.equal(r.body.status, "UP"); });
test("unknown path is 404 with error body", async () => { const r = await call("GET", "/nope"); assert.equal(r.status, 404); assert.equal(r.body.error.code, "NOT_FOUND"); });
const req = (cr, checks = ["sanctions", "pep", "adverse_media"]) => ({ correlationId: "BAO-001", subject: { type: "company", crNumber: cr, name: "Test Co LLC" }, checks });
test("registry returns a full profile", async () => {
  const r = await call("GET", "/registry/v1/companies/1234567");
  assert.equal(r.status, 200);
  for (const k of ["legalName", "status", "incorporationDate", "activities", "directors", "ubos"]) assert.ok(k in r.body, k);
});
test("registry 404 for CR starting with 0, 400 for bad CR", async () => {
  assert.equal((await call("GET", "/registry/v1/companies/0123")).status, 404);
  assert.equal((await call("GET", "/registry/v1/companies/ABC")).status, 400);
});
test("screening outcome follows CR first digit", async () => {
  const hit = await call("POST", "/screening/v1/checks", req("7001234"));
  assert.equal(hit.status, 200); assert.equal(hit.body.result, "HIT"); assert.equal(hit.body.status, "COMPLETED"); assert.ok(hit.body.matches.length > 0); assert.ok(hit.body.score >= 85);
  assert.equal((await call("POST", "/screening/v1/checks", req("5001234"))).body.result, "REVIEW");
  const clear = await call("POST", "/screening/v1/checks", req("1001234"));
  assert.equal(clear.body.result, "CLEAR"); assert.deepEqual(clear.body.matches, []); assert.ok(clear.body.score < 20);
});
test("screening is deterministic and retrievable", async () => {
  const a = await call("POST", "/screening/v1/checks", req("7009999"));
  const b = await call("POST", "/screening/v1/checks", req("7009999"));
  assert.equal(a.body.checkId, b.body.checkId); assert.equal(a.body.score, b.body.score);
  const g = await call("GET", `/screening/v1/checks/${a.body.checkId}`);
  assert.equal(g.status, 200); assert.equal(g.body.result, "HIT");
  assert.equal((await call("GET", "/screening/v1/checks/SCR-NOPE")).status, 404);
});
test("screening validation errors", async () => {
  const r = await call("POST", "/screening/v1/checks", { subject: { type: "x" }, checks: ["bogus"] });
  assert.equal(r.status, 400); assert.equal(r.body.error.code, "VALIDATION_ERROR"); assert.ok(r.body.error.details.length >= 4);
  assert.equal((await call("POST", "/screening/v1/checks", "{bad")).body.error.code, "INVALID_JSON");
});
