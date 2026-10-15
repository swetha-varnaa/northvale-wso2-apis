'use strict';
const { createServer, send, error, hash, isStr } = require('./http');

const limitsFor = (id) => {
  const h = hash(id);
  const daily = 20000 + (h % 5) * 10000;
  const monthly = daily * 10;
  const usedDaily = Math.round(daily * ((h >>> 3) % 60) / 100);
  const usedMonthly = Math.round(monthly * ((h >>> 5) % 70) / 100);
  return { daily, monthly, usedDaily, usedMonthly };
};

const routes = [
  { method: 'GET', pattern: /^\/payments\/v1\/limits\/([A-Za-z0-9_-]+)$/, handler: (req, res, m) => {
      const l = limitsFor(m[1]);
      send(res, 200, { customerId: m[1], currency: 'AED', dailyLimit: l.daily, monthlyLimit: l.monthly,
        dailyRemaining: l.daily - l.usedDaily, monthlyRemaining: l.monthly - l.usedMonthly, asOf: '2026-10-14T08:00:00Z' });
  } },
  { method: 'POST', pattern: /^\/payments\/v1\/limits\/check$/, handler: (req, res, m, b) => {
      if (!isStr(b.customerId) || typeof b.amount !== 'number' || !(b.amount > 0) || !isStr(b.currency)) {
        return error(res, 400, 'INVALID_REQUEST', 'customerId, amount (> 0) and currency are required');
      }
      const l = limitsFor(b.customerId);
      const dailyLeft = l.daily - l.usedDaily, monthlyLeft = l.monthly - l.usedMonthly;
      const withinBoth = b.amount <= dailyLeft && b.amount <= monthlyLeft;
      const decision = withinBoth && b.amount <= 50000 ? 'ALLOW' : 'REVIEW';
      const reason = !withinBoth ? 'Amount exceeds remaining limit' : (decision === 'REVIEW' ? 'Amount above single-payment threshold' : 'Within limits');
      send(res, 200, { customerId: b.customerId, amount: b.amount, currency: b.currency, decision, reason, dailyRemaining: dailyLeft, monthlyRemaining: monthlyLeft });
  } },
];
const createApp = () => createServer('payment-limits', routes);
module.exports = { createApp };
