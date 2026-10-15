'use strict';
const { createServer, send, error, hash, isStr } = require('./http');

const RISKY = { GAMBLING: 25, CRYPTO: 22, JEWELRY: 12, ELECTRONICS: 8, TRAVEL: 5, GROCERY: 0, FUEL: 0 };
const HIGH_RISK_COUNTRIES = ['NG', 'RU', 'KP', 'IR', 'SY'];

const routes = [
  { method: 'POST', pattern: /^\/fraud\/v1\/score$/, handler: (req, res, m, b) => {
      if (!isStr(b.transactionId) || typeof b.amount !== 'number' || !(b.amount > 0) || !isStr(b.merchantCategory) || !isStr(b.country)) {
        return error(res, 400, 'INVALID_REQUEST', 'transactionId, amount (> 0), merchantCategory and country are required');
      }
      const cat = b.merchantCategory.toUpperCase(); const country = b.country.toUpperCase();
      const factors = [];
      let score = hash(b.transactionId) % 15;
      const amt = Math.min(40, Math.floor(b.amount / 2500) * 5);
      if (amt) { score += amt; factors.push('HIGH_AMOUNT'); }
      if (RISKY[cat]) { score += RISKY[cat]; factors.push('RISKY_MERCHANT_CATEGORY'); }
      if (HIGH_RISK_COUNTRIES.includes(country)) { score += 30; factors.push('HIGH_RISK_COUNTRY'); }
      else if (country !== 'AE') { score += 10; factors.push('FOREIGN_COUNTRY'); }
      score = Math.min(100, score);
      const band = score >= 70 ? 'HIGH' : score >= 40 ? 'MEDIUM' : 'LOW';
      send(res, 200, { transactionId: b.transactionId, score, band, factors });
  } },
];
const createApp = () => createServer('fraud-score', routes);
module.exports = { createApp };
