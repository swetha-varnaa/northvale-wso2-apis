'use strict';
const { createServer, send, error, hash } = require('./http');

const RATES = { USD: 3.6725, EUR: 4.2810, GBP: 4.9120, INR: 0.0437, SAR: 0.9793, JPY: 0.0243 };
const quote = (from, to) => {
  const f = from === 'AED' ? 1 : RATES[from]; const t = to === 'AED' ? 1 : RATES[to];
  return { from, to, rate: Number((f / t).toFixed(6)), asOf: '2026-10-14T08:00:00Z' };
};
const known = (c) => c === 'AED' || Object.prototype.hasOwnProperty.call(RATES, c);
const routes = [
  { method: 'GET', pattern: /^\/fx\/v1\/currencies$/, handler: (req, res) => send(res, 200, { base: 'AED', currencies: ['AED', ...Object.keys(RATES)] }) },
  { method: 'GET', pattern: /^\/fx\/v1\/rates$/, handler: (req, res, m, b, q) => {
      const from = (q.get('from') || 'USD').toUpperCase(); const to = (q.get('to') || 'AED').toUpperCase();
      if (!known(from) || !known(to)) return error(res, 400, 'VALIDATION_ERROR', 'Unknown currency', [`from=${from}`, `to=${to}`]);
      send(res, 200, quote(from, to));
  } },
];

const createApp = () => createServer('fx-rates', routes);
module.exports = { createApp };
