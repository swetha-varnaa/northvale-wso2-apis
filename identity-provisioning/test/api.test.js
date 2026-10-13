const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path, body) => { const res = await fetch(base + path, { method, headers: { "Content-Type": "application/json" }, body: body === undefined ? undefined : (typeof body === "string" ? body : JSON.stringify(body)) }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); assert.equal(r.body.status, "UP"); });
test("unknown path is 404 with error body", async () => { const r = await call("GET", "/nope"); assert.equal(r.status, 404); assert.equal(r.body.error.code, "NOT_FOUND"); });
const body = { employeeId: "EMP-1042", fullName: "Layla Haddad", email: "layla.haddad@example.com", department: "Relationship Banking", role: "Relationship Manager", startDate: "2026-11-01", systems: ["email", "core-banking", "crm", "vpn"] };
test("joiner lifecycle: 202 in progress, GET completed, DELETE disabled", async () => {
  const c = await call("POST", "/provisioning/v1/accounts", body);
  assert.equal(c.status, 202); assert.equal(c.body.status, "IN_PROGRESS"); assert.equal(c.body.accounts.length, 4);
  assert.ok(c.body.accounts.every((a) => a.username && a.entitlements.length));
  const g = await call("GET", `/provisioning/v1/accounts/${c.body.requestId}`);
  assert.equal(g.body.status, "COMPLETED"); assert.ok(g.body.accounts.every((a) => a.status === "ACTIVE"));
  const d = await call("DELETE", `/provisioning/v1/accounts/${c.body.requestId}`);
  assert.equal(d.status, 200); assert.equal(d.body.status, "DEPROVISIONED"); assert.ok(d.body.accounts.every((a) => a.status === "DISABLED"));
});
test("same employee and systems give same requestId and usernames", async () => {
  const a = await call("POST", "/provisioning/v1/accounts", body);
  const b = await call("POST", "/provisioning/v1/accounts", body);
  assert.equal(a.body.requestId, b.body.requestId);
  assert.deepEqual(a.body.accounts.map((x) => x.username), b.body.accounts.map((x) => x.username));
});
test("validation errors and 404", async () => {
  const r = await call("POST", "/provisioning/v1/accounts", { ...body, email: "nope", startDate: "01/11/2026", systems: ["fax"] });
  assert.equal(r.status, 400); assert.equal(r.body.error.details.length, 3);
  assert.equal((await call("GET", "/provisioning/v1/accounts/PRV-NOPE")).status, 404);
  assert.equal((await call("DELETE", "/provisioning/v1/accounts/PRV-NOPE")).status, 404);
});
