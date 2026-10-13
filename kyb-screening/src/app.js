'use strict';
// KYB registry lookup and sanctions / PEP / adverse-media screening (mock).
// Outcome is fixed by the first digit of the CR number so demos repeat:
//   7xxxx -> HIT, 5xxxx -> REVIEW, anything else -> CLEAR.
const { send, error, hash, shortId, createServer, isStr, log } = require('./http');

const CR_RE = /^[0-9]{4,12}$/;
const ALLOWED_CHECKS = ['sanctions', 'pep', 'adverse_media'];
const SUBJECT_TYPES = ['company', 'individual'];
const checks = new Map(); // checkId -> result (in-memory; also rebuilt deterministically)

const ACTIVITIES = [
  { code: '4690', description: 'General trading' },
  { code: '6201', description: 'Software development' },
  { code: '4923', description: 'Freight transport by road' },
  { code: '7020', description: 'Management consultancy' },
  { code: '4711', description: 'Retail sale in supermarkets' },
];
const FIRST = ['Omar', 'Layla', 'Rashid', 'Priya', 'Daniel', 'Fatima', 'Arjun', 'Mariam'];
const LAST = ['Al Mansoori', 'Haddad', 'Menon', 'Clarke', 'Al Suwaidi', 'Rahman', 'Kapoor', 'Nasser'];
const NAMES = ['Gulf Horizon Trading', 'Falcon Ridge Logistics', 'Desert Pearl Technologies', 'Marina Bay Consultancy', 'Oasis Fresh Foods'];

function companyProfile(crNumber) {
  const h = hash(crNumber);
  const person = (i) => `${FIRST[(h >> i) % FIRST.length]} ${LAST[(h >> (i + 3)) % LAST.length]}`;
  const year = 2008 + (h % 16);
  const status = crNumber.startsWith('9') ? 'SUSPENDED' : 'ACTIVE';
  return {
    crNumber,
    legalName: `${NAMES[h % NAMES.length]} LLC`,
    status,
    legalForm: 'Limited Liability Company',
    jurisdiction: 'AE-DU',
    incorporationDate: `${year}-${String((h % 12) + 1).padStart(2, '0')}-${String((h % 27) + 1).padStart(2, '0')}`,
    registeredAddress: `Office ${100 + (h % 900)}, Business Bay, Dubai, UAE`,
    activities: [ACTIVITIES[h % ACTIVITIES.length], ACTIVITIES[(h + 2) % ACTIVITIES.length]],
    directors: [
      { name: person(1), role: 'Managing Director', appointedDate: `${year}-03-01` },
      { name: person(5), role: 'Director', appointedDate: `${year + 1}-06-15` },
    ],
    ubos: [
      { name: person(1), nationality: 'AE', ownershipPercent: 60 },
      { name: person(7), nationality: 'IN', ownershipPercent: 40 },
    ],
    source: 'Northvale mock registry (demo data)',
  };
}

function outcomeFor(crNumber) {
  if (crNumber.startsWith('7')) return 'HIT';
  if (crNumber.startsWith('5')) return 'REVIEW';
  return 'CLEAR';
}

function runScreening(input) {
  const { correlationId, subject, checks: requested } = input;
  const result = outcomeFor(subject.crNumber);
  const h = hash(subject.crNumber);
  const checkId = shortId('SCR', `${subject.crNumber}|${requested.slice().sort().join(',')}`);
  const matches = [];
  if (result === 'HIT' && requested.includes('sanctions')) {
    matches.push({ list: 'sanctions', source: 'Consolidated Sanctions List (mock)', matchedName: subject.name, matchScore: 92, reason: 'Exact name and jurisdiction match' });
  }
  if (result !== 'CLEAR' && requested.includes('pep')) {
    matches.push({ list: 'pep', source: 'PEP Register (mock)', matchedName: 'Related director', matchScore: result === 'HIT' ? 81 : 64, reason: 'Director shares name with a listed politically exposed person' });
  }
  if (result !== 'CLEAR' && requested.includes('adverse_media')) {
    matches.push({ list: 'adverse_media', source: 'News screening (mock)', matchedName: subject.name, matchScore: 55, reason: 'Article mentions a payment dispute' });
  }
  const score = result === 'HIT' ? 85 + (h % 15) : result === 'REVIEW' ? 45 + (h % 25) : h % 20;
  return {
    checkId,
    correlationId,
    status: 'COMPLETED',
    result,
    score,
    checksPerformed: requested,
    matches,
    screenedAt: new Date().toISOString(),
  };
}

function validateScreening(b) {
  const errs = [];
  if (!isStr(b.correlationId)) errs.push('correlationId is required');
  if (!b.subject || typeof b.subject !== 'object') errs.push('subject is required');
  else {
    if (!SUBJECT_TYPES.includes(b.subject.type)) errs.push(`subject.type must be one of ${SUBJECT_TYPES.join(', ')}`);
    if (!isStr(b.subject.crNumber) || !CR_RE.test(b.subject.crNumber)) errs.push('subject.crNumber must be 4-12 digits');
    if (!isStr(b.subject.name)) errs.push('subject.name is required');
  }
  if (!Array.isArray(b.checks) || b.checks.length === 0) errs.push('checks must be a non-empty array');
  else if (b.checks.some((c) => !ALLOWED_CHECKS.includes(c))) errs.push(`checks may contain only ${ALLOWED_CHECKS.join(', ')}`);
  return errs;
}

const routes = [
  {
    method: 'GET', pattern: /^\/registry\/v1\/companies\/([^/]+)$/,
    handler: (req, res, m) => {
      const cr = decodeURIComponent(m[1]);
      if (!CR_RE.test(cr)) return error(res, 400, 'VALIDATION_ERROR', 'crNumber must be 4-12 digits');
      if (cr.startsWith('0')) return error(res, 404, 'NOT_FOUND', `No company registered under ${cr}`);
      send(res, 200, companyProfile(cr));
    },
  },
  {
    method: 'POST', pattern: /^\/screening\/v1\/checks$/,
    handler: (req, res, m, body) => {
      const errs = validateScreening(body);
      if (errs.length) return error(res, 400, 'VALIDATION_ERROR', 'Request is invalid', errs);
      const out = runScreening(body);
      checks.set(out.checkId, out);
      log('info', 'screening', { checkId: out.checkId, result: out.result });
      send(res, 200, out);
    },
  },
  {
    method: 'GET', pattern: /^\/screening\/v1\/checks\/([^/]+)$/,
    handler: (req, res, m) => {
      const found = checks.get(decodeURIComponent(m[1]));
      if (!found) return error(res, 404, 'NOT_FOUND', 'Check not found');
      send(res, 200, found);
    },
  },
];

const createApp = () => createServer('kyb-screening', routes);
module.exports = { createApp, outcomeFor };
