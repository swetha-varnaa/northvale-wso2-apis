'use strict';
// Workforce calendar: what a leave request really costs (mock).
// Working days use the UAE weekend (Saturday, Sunday) and the 2026 holiday
// list in holidays-ae-2026.json (approximate, for demo).
const { send, error, hash, createServer, isStr, isDate, log } = require('./http');
const CAL = require('./holidays-ae-2026.json');

const LEAVE_TYPES = ['annual', 'sick', 'unpaid', 'maternity', 'compassionate'];
const HOLIDAY_SET = new Map(CAL.holidays.map((h) => [h.date, h]));

const day = (s) => new Date(s + 'T00:00:00Z');
const iso = (d) => d.toISOString().slice(0, 10);

function leaveImpact(b) {
  const from = day(b.fromDate);
  const to = day(b.toDate);
  let calendarDays = 0, workingDays = 0, weekendDays = 0;
  const publicHolidaysInRange = [];
  for (let d = new Date(from); d <= to; d.setUTCDate(d.getUTCDate() + 1)) {
    calendarDays++;
    const dow = d.getUTCDay();
    const hol = HOLIDAY_SET.get(iso(d));
    if (hol) publicHolidaysInRange.push({ date: hol.date, name: hol.name });
    if (dow === 0 || dow === 6) weekendDays++;
    else if (!hol) workingDays++;
  }

  // Team picture is fixed per department and date range, so demos repeat.
  const h = hash(`${b.department.toLowerCase()}|${b.fromDate}|${b.toDate}`);
  const teamSize = 6 + (hash(b.department.toLowerCase()) % 10);
  const othersOffInRange = h % Math.min(5, teamSize);
  const ratio = othersOffInRange / teamSize;
  const coverageRisk = ratio >= 0.3 ? 'HIGH' : ratio >= 0.15 ? 'MEDIUM' : 'LOW';

  const unpaidDays = b.leaveType === 'unpaid' ? workingDays : 0;
  const policyChecks = [];
  const add = (code, result, message) => policyChecks.push({ code, result, message });
  if (b.leaveType === 'annual') add('ANNUAL_MAX_CONSECUTIVE', workingDays <= 30 ? 'PASS' : 'FAIL', `Annual leave of ${workingDays} working days (limit 30 per request)`);
  if (b.leaveType === 'sick') add('SICK_CERTIFICATE', workingDays > 2 ? 'WARN' : 'PASS', workingDays > 2 ? 'Medical certificate required for more than 2 working days' : 'No certificate needed');
  if (b.leaveType === 'maternity') add('MATERNITY_ENTITLEMENT', calendarDays <= 60 ? 'PASS' : 'WARN', 'UAE private-sector maternity leave is 60 days (45 full pay, 15 half pay)');
  if (b.leaveType === 'compassionate') add('COMPASSIONATE_MAX', calendarDays <= 5 ? 'PASS' : 'WARN', 'Compassionate leave is up to 5 days');
  add('TEAM_COVERAGE', coverageRisk === 'HIGH' ? 'WARN' : 'PASS', `${othersOffInRange} of ${teamSize} team members already off in this range`);
  if (workingDays === 0) add('NO_WORKING_DAYS', 'WARN', 'The range covers only weekends and public holidays');

  return {
    employeeId: b.employeeId,
    leaveType: b.leaveType,
    fromDate: b.fromDate,
    toDate: b.toDate,
    calendarDays,
    workingDays,
    weekendDays,
    publicHolidaysInRange,
    teamCoverage: { teamSize, othersOffInRange, coverageRisk },
    payrollImpact: { paidDays: workingDays - unpaidDays, unpaidDays },
    policyChecks,
    calendarNote: CAL.note,
  };
}

function validate(b) {
  const errs = [];
  if (!isStr(b.employeeId)) errs.push('employeeId is required');
  if (!isStr(b.department)) errs.push('department is required');
  if (!isDate(b.fromDate)) errs.push('fromDate must be YYYY-MM-DD');
  if (!isDate(b.toDate)) errs.push('toDate must be YYYY-MM-DD');
  if (!LEAVE_TYPES.includes(b.leaveType)) errs.push(`leaveType must be one of ${LEAVE_TYPES.join(', ')}`);
  if (isDate(b.fromDate) && isDate(b.toDate)) {
    if (b.toDate < b.fromDate) errs.push('toDate must be on or after fromDate');
    if (!b.fromDate.startsWith(String(CAL.year)) || !b.toDate.startsWith(String(CAL.year))) errs.push(`dates must fall in ${CAL.year} (the only calendar loaded)`);
  }
  return errs;
}

const routes = [
  {
    method: 'POST', pattern: /^\/workforce\/v1\/leave-impact$/,
    handler: (req, res, m, b) => {
      const errs = validate(b);
      if (errs.length) return error(res, 400, 'VALIDATION_ERROR', 'Request is invalid', errs);
      const out = leaveImpact(b);
      log('info', 'leave-impact', { workingDays: out.workingDays, risk: out.teamCoverage.coverageRisk });
      send(res, 200, out);
    },
  },
  {
    method: 'GET', pattern: /^\/workforce\/v1\/holidays$/,
    handler: (req, res, m, b, q) => {
      const year = q.get('year') || String(CAL.year);
      if (!/^\d{4}$/.test(year)) return error(res, 400, 'VALIDATION_ERROR', 'year must be a 4-digit year');
      if (Number(year) !== CAL.year) return error(res, 404, 'NOT_FOUND', `No holiday calendar loaded for ${year}`);
      send(res, 200, CAL);
    },
  },
];

const createApp = () => createServer('workforce-calendar', routes);
module.exports = { createApp, leaveImpact };
