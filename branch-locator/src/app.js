'use strict';
const { createServer, send, error, hash } = require('./http');

const BRANCHES = [
  { id: 'BR-001', name: 'DIFC Head Office', city: 'Dubai', address: 'Gate Village 4, DIFC', atm: true, openUntil: '17:00' },
  { id: 'BR-002', name: 'Business Bay', city: 'Dubai', address: 'Bay Square 7', atm: true, openUntil: '16:00' },
  { id: 'BR-003', name: 'Al Maryah Island', city: 'Abu Dhabi', address: 'Sowwah Square', atm: true, openUntil: '17:00' },
  { id: 'BR-004', name: 'Sharjah Operations Centre', city: 'Sharjah', address: 'Al Majaz 2', atm: false, openUntil: '15:00' },
];
const routes = [
  { method: 'GET', pattern: /^\/branches\/v1\/branches$/, handler: (req, res, m, b, q) => {
      const city = q.get('city');
      const rows = city ? BRANCHES.filter((x) => x.city.toLowerCase() === city.toLowerCase()) : BRANCHES;
      send(res, 200, { count: rows.length, branches: rows });
  } },
  { method: 'GET', pattern: /^\/branches\/v1\/branches\/(BR-\d{3})$/, handler: (req, res, m) => {
      const row = BRANCHES.find((x) => x.id === m[1]);
      if (!row) return error(res, 404, 'NOT_FOUND', 'No such branch');
      send(res, 200, row);
  } },
];

const createApp = () => createServer('branch-locator', routes);
module.exports = { createApp };
