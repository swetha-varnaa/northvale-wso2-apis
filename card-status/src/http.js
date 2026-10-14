'use strict';
// Shared HTTP helpers. Copied into each service as src/http.js so every
// service folder builds on its own (one folder = one Choreo component).
// Edit _shared/http.js, then run `node scripts/sync-shared.js` at the repo root.
const crypto = require('node:crypto');

function log(level, msg, fields = {}) {
  // Structured JSON log. Callers pass ids and codes only, never names, emails or national ids.
  process.stdout.write(JSON.stringify({ ts: new Date().toISOString(), level, msg, ...fields }) + '\n');
}

function send(res, status, body) {
  const data = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(data);
}

function error(res, status, code, message, details) {
  send(res, status, { error: { code, message, ...(details ? { details } : {}) } });
}

function readJson(req) {
  return new Promise((resolve) => {
    let raw = '';
    req.on('data', (c) => { raw += c; if (raw.length > 1e6) req.destroy(); });
    req.on('end', () => {
      if (!raw) return resolve({ ok: true, body: {} });
      try { resolve({ ok: true, body: JSON.parse(raw) }); } catch { resolve({ ok: false }); }
    });
  });
}

// Deterministic 32-bit hash so the same input always gives the same demo answer.
function hash(str) {
  let h = 0x811c9dc5;
  for (const ch of String(str)) { h ^= ch.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
  return h;
}

function shortId(prefix, seed) {
  return prefix + '-' + crypto.createHash('sha256').update(String(seed)).digest('hex').slice(0, 10).toUpperCase();
}

// routes: [{ method, pattern: RegExp, handler(req, res, match, body) }]
function createServer(serviceName, routes) {
  const http = require('node:http');
  return http.createServer(async (req, res) => {
    const started = Date.now();
    const url = new URL(req.url, 'http://localhost');
    res.on('finish', () => log('info', 'request', { service: serviceName, method: req.method, path: url.pathname, status: res.statusCode, ms: Date.now() - started }));
    try {
      if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { status: 'UP', service: serviceName });
      const pathMatches = routes.filter((r) => r.pattern.test(url.pathname));
      if (!pathMatches.length) return error(res, 404, 'NOT_FOUND', 'No such resource');
      const route = pathMatches.find((r) => r.method === req.method);
      if (!route) return error(res, 405, 'METHOD_NOT_ALLOWED', `Method ${req.method} not allowed here`);
      let body = {};
      if (req.method === 'POST' || req.method === 'PUT') {
        const parsed = await readJson(req);
        if (!parsed.ok) return error(res, 400, 'INVALID_JSON', 'Request body is not valid JSON');
        body = parsed.body;
      }
      await route.handler(req, res, url.pathname.match(route.pattern), body, url.searchParams);
    } catch (e) {
      log('error', 'unhandled', { service: serviceName, err: e.message });
      error(res, 500, 'INTERNAL_ERROR', 'Unexpected error');
    }
  });
}

const isStr = (v) => typeof v === 'string' && v.trim().length > 0;
const isDate = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) && !isNaN(Date.parse(v + 'T00:00:00Z'));

module.exports = { log, send, error, hash, shortId, createServer, isStr, isDate };
