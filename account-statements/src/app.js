'use strict';
const { createServer, send, error, hash } = require('./http');

const MERCHANTS = [['Carrefour Dubai Mall', -412.5], ['Salary Northvale Payroll', 18500], ['DEWA Utility Bill', -386.2], ['Careem Rides', -64], ['Noon Online Shopping', -239.9], ['ATM Withdrawal Deira', -1000], ['Transfer from Savings', 2500]];

const routes = [
  { method: 'GET', pattern: /^\/statements\/v1\/accounts\/([A-Za-z0-9_-]+)\/statements$/, handler: (req, res, m, body, q) => {
      const month = q.get('month');
      if (!month || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) return error(res, 400, 'INVALID_MONTH', 'month must be YYYY-MM');
      const accountId = m[1]; const h = hash(accountId + month);
      const opening = 10000 + (h % 90000);
      let bal = opening; const tx = [];
      for (let i = 0; i < 5; i++) {
        const [desc, base] = MERCHANTS[(h + i * 3) % MERCHANTS.length];
        const amount = Math.round(base * (1 + ((h >>> i) % 5) / 10) * 100) / 100;
        bal = Math.round((bal + amount) * 100) / 100;
        tx.push({ date: month + '-' + String(3 + i * 5).padStart(2, '0'), description: desc, amount, balanceAfter: bal });
      }
      const credits = tx.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0);
      const debits = tx.filter((t) => t.amount < 0).reduce((s, t) => s + t.amount, 0);
      send(res, 200, { accountId, month, currency: 'AED', openingBalance: opening, closingBalance: bal,
        totalCredits: Math.round(credits * 100) / 100, totalDebits: Math.round(Math.abs(debits) * 100) / 100, transactionCount: tx.length, transactions: tx });
  } },
];
const createApp = () => createServer('account-statements', routes);
module.exports = { createApp };
