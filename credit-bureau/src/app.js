'use strict';
// Credit bureau score and report (mock). The score is derived from a hash of
// nationalIdOrCr, so the same applicant always gets the same score.
const { send, error, hash, shortId, createServer, isStr, log } = require('./http');

const TYPES = ['business', 'individual'];
const reports = new Map();

function band(score) {
  if (score >= 800) return 'A';
  if (score >= 700) return 'B';
  if (score >= 600) return 'C';
  if (score >= 500) return 'D';
  return 'E';
}

function scoreApplicant(b) {
  const h = hash(b.nationalIdOrCr);
  const score = 300 + (h % 601); // 300..900
  const bnd = band(score);
  const pdTable = { A: 0.008, B: 0.021, C: 0.054, D: 0.12, E: 0.27 };
  const activeFacilities = h % 6;
  const totalExposure = activeFacilities * (25000 + (h % 9) * 15000);
  const delinquencies12m = bnd === 'A' || bnd === 'B' ? 0 : bnd === 'C' ? h % 2 : 1 + (h % 4);
  const factors = [];
  if (delinquencies12m > 0) factors.push({ code: 'DELQ', impact: 'NEGATIVE', description: `${delinquencies12m} late payment(s) in the last 12 months` });
  if (totalExposure > b.requestedAmount * 2) factors.push({ code: 'EXPO', impact: 'NEGATIVE', description: 'Existing exposure is more than twice the requested amount' });
  if (activeFacilities === 0) factors.push({ code: 'THIN', impact: 'NEUTRAL', description: 'Thin credit file: no active facilities' });
  if (bnd === 'A' || bnd === 'B') factors.push({ code: 'HIST', impact: 'POSITIVE', description: 'Long and clean repayment history' });
  if (factors.length === 0) factors.push({ code: 'STBL', impact: 'NEUTRAL', description: 'Stable credit behaviour' });
  let recommendation = bnd === 'A' || bnd === 'B' ? 'APPROVE' : bnd === 'C' ? 'REVIEW' : 'DECLINE';
  if (recommendation === 'APPROVE' && b.requestedAmount > 5000000) recommendation = 'REVIEW';
  return {
    scoreId: shortId('CBS', b.nationalIdOrCr),
    applicantType: b.applicantType,
    productCode: b.productCode,
    requestedAmount: b.requestedAmount,
    score,
    band: bnd,
    probabilityOfDefault: pdTable[bnd],
    totalExposure,
    currency: 'AED',
    activeFacilities,
    delinquencies12m,
    factors,
    recommendation,
    generatedAt: new Date().toISOString(),
  };
}

function validate(b) {
  const errs = [];
  if (!TYPES.includes(b.applicantType)) errs.push('applicantType must be business or individual');
  if (!isStr(b.nationalIdOrCr) || !/^[A-Za-z0-9-]{4,20}$/.test(b.nationalIdOrCr)) errs.push('nationalIdOrCr must be 4-20 letters, digits or dashes');
  if (!isStr(b.name)) errs.push('name is required');
  if (typeof b.requestedAmount !== 'number' || !(b.requestedAmount > 0)) errs.push('requestedAmount must be a positive number');
  if (!isStr(b.productCode)) errs.push('productCode is required');
  return errs;
}

const routes = [
  {
    method: 'POST', pattern: /^\/credit\/v1\/scores$/,
    handler: (req, res, m, body) => {
      const errs = validate(body);
      if (errs.length) return error(res, 400, 'VALIDATION_ERROR', 'Request is invalid', errs);
      const out = scoreApplicant(body);
      reports.set(out.scoreId, out);
      log('info', 'score', { scoreId: out.scoreId, band: out.band });
      send(res, 200, out);
    },
  },
  {
    method: 'GET', pattern: /^\/credit\/v1\/reports\/([^/]+)$/,
    handler: (req, res, m) => {
      const r = reports.get(decodeURIComponent(m[1]));
      if (!r) return error(res, 404, 'NOT_FOUND', 'Score not found');
      send(res, 200, {
        ...r,
        facilities: Array.from({ length: r.activeFacilities }, (_, i) => ({
          type: ['TERM_LOAN', 'OVERDRAFT', 'CREDIT_CARD', 'TRADE_FINANCE'][i % 4],
          lender: `Bank ${String.fromCharCode(65 + i)} (mock)`,
          outstanding: Math.round(r.totalExposure / r.activeFacilities),
          status: i < r.delinquencies12m ? 'PAST_DUE' : 'CURRENT',
        })),
      });
    },
  },
];

const createApp = () => createServer('credit-bureau', routes);
module.exports = { createApp, band };
