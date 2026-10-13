const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path, body) => { const res = await fetch(base + path, { method, headers: { "Content-Type": "application/json" }, body: body === undefined ? undefined : (typeof body === "string" ? body : JSON.stringify(body)) }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); assert.equal(r.body.status, "UP"); });
test("unknown path is 404 with error body", async () => { const r = await call("GET", "/nope"); assert.equal(r.status, 404); assert.equal(r.body.error.code, "NOT_FOUND"); });
const body = (id, amt = 250000) => ({ applicantType: "business", nationalIdOrCr: id, name: "Test Co LLC", requestedAmount: amt, productCode: "SME-TL" });
test("score has every field in range", async () => {
  const r = await call("POST", "/credit/v1/scores", body("1234567"));
  assert.equal(r.status, 200);
  assert.ok(r.body.score >= 300 && r.body.score <= 900);
  assert.match(r.body.band, /^[A-E]$/);
  assert.ok(["APPROVE", "REVIEW", "DECLINE"].includes(r.body.recommendation));
  for (const k of ["scoreId", "probabilityOfDefault", "totalExposure", "activeFacilities", "delinquencies12m", "factors"]) assert.ok(k in r.body, k);
});
test("same id gives same score; report is retrievable", async () => {
  const a = await call("POST", "/credit/v1/scores", body("784-1990-1234567-1"));
  const b = await call("POST", "/credit/v1/scores", body("784-1990-1234567-1"));
  assert.equal(a.body.scoreId, b.body.scoreId); assert.equal(a.body.score, b.body.score);
  const rep = await call("GET", `/credit/v1/reports/${a.body.scoreId}`);
  assert.equal(rep.status, 200); assert.equal(rep.body.facilities.length, a.body.activeFacilities);
  assert.equal((await call("GET", "/credit/v1/reports/CBS-NOPE")).status, 404);
});
test("different ids spread across bands", async () => {
  const bands = new Set();
  for (let i = 0; i < 40; i++) bands.add((await call("POST", "/credit/v1/scores", body("CR" + (1000 + i)))).body.band);
  assert.ok(bands.size >= 3, [...bands].join());
});
test("validation errors", async () => {
  const r = await call("POST", "/credit/v1/scores", { applicantType: "alien", requestedAmount: -5 });
  assert.equal(r.status, 400); assert.equal(r.body.error.code, "VALIDATION_ERROR"); assert.equal(r.body.error.details.length, 5);
});
