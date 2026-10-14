'use strict';
const { createServer, send, error, hash } = require('./http');

const STATES = ['ACTIVE', 'BLOCKED', 'EXPIRED', 'PENDING_ACTIVATION'];
const routes = [
  { method: 'GET', pattern: /^\/cards\/v1\/cards\/(\d{4})\/status$/, handler: (req, res, m) => {
      const last4 = m[1]; const h = hash(last4);
      send(res, 200, { cardLast4: last4, status: STATES[h % STATES.length], dailyLimitAed: 5000 + (h % 5) * 5000, contactless: h % 2 === 0, checkedAt: '2026-10-14T08:00:00Z' });
  } },
];

const createApp = () => createServer('card-status', routes);
module.exports = { createApp };
