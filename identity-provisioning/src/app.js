'use strict';
// Identity provisioning for joiners and leavers (mock).
// POST creates accounts (202 IN_PROGRESS); GET returns COMPLETED once the
// request exists; DELETE disables every account (offboarding).
const { send, error, shortId, createServer, isStr, isDate, log } = require('./http');

const SYSTEMS = ['email', 'core-banking', 'crm', 'vpn'];
const requests = new Map();

const ENTITLEMENTS = {
  email: () => ['mailbox', 'calendar'],
  'core-banking': (role) => (/manager|head/i.test(role) ? ['view-accounts', 'approve-transactions'] : ['view-accounts', 'initiate-transactions']),
  crm: (role, dept) => ['view-customers', ...(/sales|relationship/i.test(dept) ? ['edit-opportunities'] : [])],
  vpn: () => ['remote-access'],
};

function username(fullName, employeeId, system) {
  const base = fullName.toLowerCase().replace(/[^a-z ]/g, '').trim().split(/\s+/);
  const u = (base[0][0] + (base[base.length - 1] || '')).slice(0, 12) + employeeId.replace(/\D/g, '').slice(-3);
  return system === 'email' ? `${u}@northvale.example` : u;
}

function validate(b) {
  const errs = [];
  if (!isStr(b.employeeId) || !/^[A-Za-z0-9-]{3,20}$/.test(b.employeeId)) errs.push('employeeId must be 3-20 letters, digits or dashes');
  if (!isStr(b.fullName) || !/[A-Za-z]/.test(b.fullName)) errs.push('fullName is required');
  if (!isStr(b.email) || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(b.email)) errs.push('email must be a valid address');
  if (!isStr(b.department)) errs.push('department is required');
  if (!isStr(b.role)) errs.push('role is required');
  if (!isDate(b.startDate)) errs.push('startDate must be YYYY-MM-DD');
  if (!Array.isArray(b.systems) || !b.systems.length) errs.push('systems must be a non-empty array');
  else if (b.systems.some((s) => !SYSTEMS.includes(s))) errs.push(`systems may contain only ${SYSTEMS.join(', ')}`);
  return errs;
}

const routes = [
  {
    method: 'POST', pattern: /^\/provisioning\/v1\/accounts$/,
    handler: (req, res, m, b) => {
      const errs = validate(b);
      if (errs.length) return error(res, 400, 'VALIDATION_ERROR', 'Request is invalid', errs);
      const requestId = shortId('PRV', `${b.employeeId}|${[...new Set(b.systems)].sort().join(',')}`);
      const rec = {
        requestId,
        employeeId: b.employeeId,
        status: 'IN_PROGRESS',
        startDate: b.startDate,
        accounts: [...new Set(b.systems)].map((system) => ({
          system,
          username: username(b.fullName, b.employeeId, system),
          status: 'PENDING',
          entitlements: ENTITLEMENTS[system](b.role, b.department),
        })),
        createdAt: new Date().toISOString(),
      };
      requests.set(requestId, rec);
      log('info', 'provision', { requestId, systems: rec.accounts.length });
      send(res, 202, rec);
    },
  },
  {
    method: 'GET', pattern: /^\/provisioning\/v1\/accounts\/([^/]+)$/,
    handler: (req, res, m) => {
      const rec = requests.get(decodeURIComponent(m[1]));
      if (!rec) return error(res, 404, 'NOT_FOUND', 'Provisioning request not found');
      // Mock completion: the first status read finishes any pending work.
      if (rec.status === 'IN_PROGRESS') {
        rec.status = 'COMPLETED';
        rec.accounts.forEach((a) => { a.status = 'ACTIVE'; });
        rec.completedAt = new Date().toISOString();
      }
      send(res, 200, rec);
    },
  },
  {
    method: 'DELETE', pattern: /^\/provisioning\/v1\/accounts\/([^/]+)$/,
    handler: (req, res, m) => {
      const rec = requests.get(decodeURIComponent(m[1]));
      if (!rec) return error(res, 404, 'NOT_FOUND', 'Provisioning request not found');
      rec.status = 'DEPROVISIONED';
      rec.accounts.forEach((a) => { a.status = 'DISABLED'; a.entitlements = []; });
      rec.deprovisionedAt = new Date().toISOString();
      log('info', 'deprovision', { requestId: rec.requestId });
      send(res, 200, rec);
    },
  },
];

const createApp = () => createServer('identity-provisioning', routes);
module.exports = { createApp };
