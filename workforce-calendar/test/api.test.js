const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../src/app");
let server, base;
before(() => new Promise((r) => { process.stdout.write = ((w) => (s, ...a) => (String(s).startsWith("{\"ts\"") ? true : w(s, ...a)))(process.stdout.write.bind(process.stdout)); server = createApp().listen(0, () => { base = `http://127.0.0.1:${server.address().port}`; r(); }); }));
after(() => new Promise((r) => server.close(r)));
const call = async (method, path, body) => { const res = await fetch(base + path, { method, headers: { "Content-Type": "application/json" }, body: body === undefined ? undefined : (typeof body === "string" ? body : JSON.stringify(body)) }); return { status: res.status, body: await res.json() }; };
test("health", async () => { const r = await call("GET", "/health"); assert.equal(r.status, 200); assert.equal(r.body.status, "UP"); });
test("unknown path is 404 with error body", async () => { const r = await call("GET", "/nope"); assert.equal(r.status, 404); assert.equal(r.body.error.code, "NOT_FOUND"); });
const body = (o = {}) => ({ employeeId: "EMP-1042", department: "Operations", fromDate: "2026-11-30", toDate: "2026-12-04", leaveType: "annual", ...o });
test("leave over National Day skips the holidays", async () => {
  const r = await call("POST", "/workforce/v1/leave-impact", body());
  assert.equal(r.status, 200);
  assert.equal(r.body.calendarDays, 5);  // Mon 30 Nov .. Fri 4 Dec
  assert.equal(r.body.workingDays, 2);   // 1-3 Dec are holidays
  assert.equal(r.body.publicHolidaysInRange.length, 3);
  assert.deepEqual(r.body.payrollImpact, { paidDays: 2, unpaidDays: 0 });
  assert.ok(["LOW", "MEDIUM", "HIGH"].includes(r.body.teamCoverage.coverageRisk));
});
test("weekend is Saturday and Sunday; unpaid leave hits payroll", async () => {
  const r = await call("POST", "/workforce/v1/leave-impact", body({ fromDate: "2026-10-12", toDate: "2026-10-18", leaveType: "unpaid" }));
  assert.equal(r.body.calendarDays, 7); assert.equal(r.body.workingDays, 5);
  assert.deepEqual(r.body.payrollImpact, { paidDays: 0, unpaidDays: 5 });
});
test("deterministic team coverage", async () => {
  const a = await call("POST", "/workforce/v1/leave-impact", body());
  const b = await call("POST", "/workforce/v1/leave-impact", body());
  assert.deepEqual(a.body.teamCoverage, b.body.teamCoverage);
});
test("holidays endpoint", async () => {
  const r = await call("GET", "/workforce/v1/holidays?year=2026");
  assert.equal(r.status, 200); assert.ok(r.body.holidays.length >= 10); assert.match(r.body.note, /Approximate, for demo/);
  assert.equal((await call("GET", "/workforce/v1/holidays?year=2030")).status, 404);
  assert.equal((await call("GET", "/workforce/v1/holidays?year=abc")).status, 400);
});
test("validation errors", async () => {
  const r = await call("POST", "/workforce/v1/leave-impact", body({ fromDate: "2026-12-10", toDate: "2026-12-01", leaveType: "holiday" }));
  assert.equal(r.status, 400); assert.equal(r.body.error.details.length, 2);
  assert.equal((await call("POST", "/workforce/v1/leave-impact", body({ fromDate: "2027-01-01", toDate: "2027-01-02" }))).status, 400);
});
