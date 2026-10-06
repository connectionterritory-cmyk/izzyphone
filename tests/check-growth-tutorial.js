// Static check: tutorial-crecimiento.html vs docs/01-IZZY-COMM-COMPENSATION-PLAN-V1-AGENT.md
// Usage: node tests/check-growth-tutorial.js
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'tutorial-crecimiento.html'), 'utf8');
const md = fs.readFileSync(path.join(root, 'docs/01-IZZY-COMM-COMPENSATION-PLAN-V1-AGENT.md'), 'utf8');

const decode = (s) => s.replace(/&amp;/g, '&');
const money = (s) => Number(s.replace(/[^0-9]/g, ''));

// ── Source of truth ──────────────────────────────────────────
function mdRows(heading) {
  const section = md.split(heading)[1].split(/\n## /)[0];
  return section
    .split('\n')
    .filter((l) => l.startsWith('|') && !/^\|[-\s|:]+\|$/.test(l) && !l.includes('Producto'))
    .map((l) => l.split('|').slice(1, -1).map((c) => c.trim()));
}
const comm = mdRows('## Comisiones por conexión');
const bonus = mdRows('## Bonos de producción de Supervisor');
const expected = {
  'commission-training': Object.fromEntries(comm.map((r) => [r[0], money(r[1])])),
  'commission-associate': Object.fromEntries(comm.map((r) => [r[0], money(r[2])])),
  'commission-supervisor': Object.fromEntries(comm.map((r) => [r[0], money(r[3])])),
  'bonus-25-49': Object.fromEntries(bonus.map((r) => [r[0], money(r[1])])),
  'bonus-50-plus': Object.fromEntries(bonus.map((r) => [r[0], money(r[2])])),
};

// ── Page ─────────────────────────────────────────────────────
function pageTable(name) {
  const m = html.match(new RegExp(`<table data-table="${name}">([\\s\\S]*?)</table>`));
  if (!m) return null;
  const out = {};
  for (const r of m[1].matchAll(/<tr data-product="([^"]+)"><th[^>]*>([^<]*)<\/th><td data-amount="(\d+)">([^<]*)<\/td>/g)) {
    const product = decode(r[1]);
    if (decode(r[2]) !== product) out['__label_mismatch__' + product] = decode(r[2]);
    if (money(r[4]) !== Number(r[3])) out['__text_mismatch__' + product] = r[4];
    out[product] = Number(r[3]);
  }
  return out;
}

const errors = [];
let products = 0, commissions = 0, bonuses = 0;
for (const [name, exp] of Object.entries(expected)) {
  const got = pageTable(name);
  if (!got) { errors.push(`missing table ${name}`); continue; }
  const keys = Object.keys(exp);
  if (Object.keys(got).length !== keys.length) errors.push(`${name}: expected ${keys.length} rows, got ${Object.keys(got).length}`);
  for (const k of keys) {
    if (got[k] !== exp[k]) errors.push(`${name} / ${k}: page=${got[k]} V1=${exp[k]}`);
  }
  for (const k of Object.keys(got)) if (k.startsWith('__')) errors.push(`${name}: ${k} -> ${got[k]}`);
  if (name.startsWith('commission')) { commissions += keys.length; products = keys.length; }
  else bonuses += keys.length;
}

// ── Banned terms ─────────────────────────────────────────────
const visible = html.replace(/<style[\s\S]*?<\/style>/g, '').replace(/<script[\s\S]*?<\/script>/g, '');
const legacy = ['Director', 'Embajador', 'Básico', 'Estándar', 'Premium', 'override', 'multi-level', 'multinivel', 'organización completa', 'Novato'];
const confidential = ['carrier_internal_payout', 'gross_margin', 'reserve', 'wholesale', 'internal payout', 'company margin', 'semáforo'];
const legacyHits = legacy.filter((t) => new RegExp(t, 'i').test(visible));
const confHits = confidential.filter((t) => new RegExp(t, 'i').test(html));

// ── Leadership wording (owner-approved 2026-10-06) ───────────
const text = visible.replace(/<[^>]+>/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ');
const eligible = [...visible.matchAll(/data-leadership="eligible">([^<]+)</g)].map((m) => decode(m[1]));
const notEligible = [...visible.matchAll(/data-leadership="not-eligible">([^<]+)</g)].map((m) => decode(m[1]));
const wantEligible = ['Spectrum 500 Mbps', 'Spectrum 1 Gig', 'AT&T Fiber 300 Mbps', 'AT&T 500 Mbps', 'AT&T 1–5 Gig', 'AT&T Air', 'Frontier 500 Mbps', 'Frontier 1 Gig'];
const wantNot = ['AT&T Celular + Línea', 'AT&T BYOD'];
if (JSON.stringify(eligible) !== JSON.stringify(wantEligible)) errors.push(`leadership eligible list mismatch: ${eligible.join(' | ')}`);
if (JSON.stringify(notEligible) !== JSON.stringify(wantNot)) errors.push(`leadership not-eligible list mismatch: ${notEligible.join(' | ')}`);
const requiredPhrases = [
  'No generan Bono de Liderazgo para ti',
  'Sus conexiones cuentan para tu pool de producción 25/50',
  'comienza cuando desarrollas a un agente y ese agente se convierte en Supervisor',
  'Cada conexión puede generar un solo Bono de Liderazgo',
  'Una sola profundidad',
  'A gana $0',
];
for (const ph of requiredPhrases) if (!text.includes(ph)) errors.push(`missing leadership phrase: ${ph}`);
if (/tu Supervisor directo/i.test(text)) errors.push('ambiguous phrase "tu Supervisor directo" must not appear');

console.log(`products=${products} commissions=${commissions} bonuses=${bonuses} (expected 10 / 30 / 20)`);
if (products !== 10 || commissions !== 30 || bonuses !== 20) errors.push('count mismatch');
if (errors.length) { console.error('PUBLIC TUTORIAL VALIDATION FAILED'); errors.forEach((e) => console.error('  -', e)); }
if (legacyHits.length) console.error('LEGACY CONTENT FOUND:', legacyHits.join(', '));
if (confHits.length) console.error('CONFIDENTIAL TERMS FOUND:', confHits.join(', '));
if (errors.length || legacyHits.length || confHits.length) process.exit(1);
console.log('OK: economics match V1; no legacy or confidential terms.');
