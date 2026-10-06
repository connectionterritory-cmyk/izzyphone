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

// ── Worked examples ("Ejemplo práctico"): every number must derive from the V1 tables ──
const attrsOf = (s) => Object.fromEntries([...s.matchAll(/([\w-]+)="([^"]*)"/g)].map((m) => [m[1], decode(m[2])]));
const plain = (s) => decode(s.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ');
const exs = [...html.matchAll(/<article class="ej[^"]*"([^>]*)>([\s\S]*?)<\/article>/g)].map((m) => ({ a: attrsOf(m[1]), body: m[2], text: plain(m[2]) }));
const ex = (k) => exs.filter((e) => e.a['data-ej'] === k);
const needed = ['level-training', 'level-associate', 'level-supervisor', 'bonus-25', 'bonus-50', 'bonus-spectrum', 'leadership', 'chargeback', 'maintenance'];
for (const k of needed) if (ex(k).length !== 1) errors.push(`example ${k}: expected exactly 1, found ${ex(k).length}`);
if (exs.length !== needed.length) errors.push(`unexpected number of examples: ${exs.length}`);
const disclaimer = 'Ejemplo ilustrativo. Las comisiones dependen de conexiones válidas y de las reglas vigentes del plan.';
for (const e of exs) if (!e.text.includes(disclaimer)) errors.push(`example ${e.a['data-ej']}: missing disclaimer`);
const $ = (n) => `$${n}`;

for (const lvl of ['training', 'associate', 'supervisor']) {
  const e = ex(`level-${lvl}`)[0];
  if (!e) continue;
  const prod = e.a['data-product'], qty = Number(e.a['data-qty']), unit = Number(e.a['data-unit']), total = Number(e.a['data-total']);
  if (prod !== 'AT&T 500 Mbps') errors.push(`level-${lvl}: must use AT&T 500 Mbps, got ${prod}`);
  if (unit !== expected[`commission-${lvl}`][prod]) errors.push(`level-${lvl}: unit ${unit} != V1 ${expected[`commission-${lvl}`][prod]}`);
  if (qty * unit !== total) errors.push(`level-${lvl}: ${qty} x ${unit} != ${total}`);
  if (!e.text.includes(`${qty} conexión × ${$(unit)} = ${$(total)}`)) errors.push(`level-${lvl}: calculation text missing/different`);
  if (!e.text.includes(`genera ${$(total)} de comisión base`)) errors.push(`level-${lvl}: result text missing/different`);
}
const progRows = [...html.matchAll(/<div class="prog-row[^"]*" data-level="(\w+)" data-amount="(\d+)"/g)].map((m) => [m[1], Number(m[2])]);
if (JSON.stringify(progRows.map((r) => r[0])) !== JSON.stringify(['training', 'associate', 'supervisor'])) errors.push('progression rows must be training, associate, supervisor');
for (const [lvl, amt] of progRows) if (amt !== expected[`commission-${lvl}`]['AT&T 500 Mbps']) errors.push(`progression ${lvl}: ${amt} != V1`);
const cmp = attrsOf((html.match(/<div class="cmp"([^>]*)>/) || [, ''])[1]);
{
  const from = expected['commission-training']['AT&T 500 Mbps'], to = expected['commission-associate']['AT&T 500 Mbps'];
  if (Number(cmp['data-from']) !== from || Number(cmp['data-to']) !== to || Number(cmp['data-diff']) !== to - from) errors.push('training->associate comparison does not match V1');
  if (!plain(html).includes(`+${$(to - from)} por la misma conexión válida`)) errors.push('comparison difference text missing');
}

const bonusCards = { 'bonus-25': ex('bonus-25')[0], 'bonus-50': ex('bonus-50')[0] };
{
  const allSteps = [];
  for (const [k, e] of Object.entries(bonusCards)) {
    if (!e) continue;
    const prod = e.a['data-product'];
    const steps = [...e.body.matchAll(/<li class="st[^"]*"([^>]*)>/g)].map((m) => attrsOf(m[1]));
    for (const s of steps) {
      const o = Number(s['data-ordinal']), base = Number(s['data-base']), bonus = Number(s['data-bonus']), total = Number(s['data-total']);
      const vBonus = o < 25 ? 0 : o <= 49 ? expected['bonus-25-49'][prod] : expected['bonus-50-plus'][prod];
      const tier = o < 25 ? 'none' : o <= 49 ? '25-49' : '50+';
      if (base !== expected['commission-supervisor'][prod]) errors.push(`${k} #${o}: base ${base} != V1`);
      if (bonus !== vBonus) errors.push(`${k} #${o}: bonus ${bonus} != V1 ${vBonus}`);
      if (s['data-tier'] !== tier) errors.push(`${k} #${o}: wrong tier ${s['data-tier']}`);
      if (total !== base + bonus) errors.push(`${k} #${o}: ${base} + ${bonus} != ${total}`);
      const fx = o < 25 ? `#${o} → ${$(total)}` : `#${o} → ${$(base)} + ${$(bonus)} = ${$(total)}`;
      if (!e.text.includes(fx)) errors.push(`${k} #${o}: formula text missing (${fx})`);
      if (!e.text.includes(`${$(total)}`)) errors.push(`${k} #${o}: total text missing`);
      allSteps.push(o);
    }
  }
  if (JSON.stringify(allSteps) !== JSON.stringify([24, 25, 49, 50])) errors.push(`bonus examples must show #24, #25, #49, #50 in order, got ${allSteps}`);
  if (bonusCards['bonus-25'] && !bonusCards['bonus-25'].text.includes('conexión #25 de tu pool')) errors.push('bonus-25: missing "conexión #25 de tu pool"');
  if (bonusCards['bonus-50']) for (const ph of ['conexión #50 de tu pool', 'No es retroactivo']) if (!bonusCards['bonus-50'].text.includes(ph)) errors.push(`bonus-50: missing "${ph}"`);
  if (bonusCards['bonus-25'] && !bonusCards['bonus-25'].text.includes(`$${expected['commission-supervisor']['AT&T 500 Mbps'] + expected['bonus-25-49']['AT&T 500 Mbps']}`)) errors.push('bonus-25: result total missing');
}
const bs = ex('bonus-spectrum')[0];
if (bs) {
  const prod = bs.a['data-product'], base = Number(bs.a['data-base']), bonus = Number(bs.a['data-bonus']), total = Number(bs.a['data-total']);
  if (base !== expected['commission-supervisor'][prod] || bonus !== expected['bonus-25-49'][prod] || total !== base + bonus) errors.push('bonus-spectrum does not match V1');
  if (!bs.text.includes(`${$(base)} + ${$(bonus)} = ${$(total)}`)) errors.push('bonus-spectrum: formula text missing');
  for (const p2 of ['AT&T 500 Mbps', 'Spectrum 1 Gig']) if (!bs.text.includes(`${p2} suma ${$(expected['bonus-25-49'][p2])}`)) errors.push(`bonus-spectrum: comparison for ${p2} missing/different`);
}

const rate = Number((md.match(/\$(\d+) por cada conexión válida de \*\*internet\*\*/) || [])[1]);
if (!rate) errors.push('could not read leadership rate from V1 doc');
if (!/Celular y BYOD no generan liderazgo/.test(md)) errors.push('V1 doc no longer states Celular/BYOD exclusion — review leadership example');
const ld = ex('leadership')[0];
if (ld) {
  const sup = Number(ld.a['data-supervisor-internet']), ag = Number(ld.a['data-agent-internet']), n = sup + ag, total = Number(ld.a['data-total']);
  if (Number(ld.a['data-rate']) !== rate) errors.push(`leadership: rate ${ld.a['data-rate']} != V1 ${rate}`);
  if (total !== n * rate) errors.push(`leadership: ${n} x ${rate} != ${total}`);
  if (Number(ld.a['data-agent-byod']) < 1) errors.push('leadership: the example must show a BYOD that does not count');
  for (const ph of [`${sup} de Carlos + ${ag} de su equipo directo elegible = ${n} conexiones elegibles`, `${n} × ${$(rate)} = ${$(total)}`, `María recibe ${$(total)} de Bono de Liderazgo en este ejemplo`, 'AT&T BYOD: $0 de liderazgo', 'Una sola profundidad', 'Un solo Bono de Liderazgo por conexión', 'no generan liderazgo para María', 'pool 25/50', 'no pagos entre agentes']) if (!ld.text.includes(ph)) errors.push(`leadership: missing "${ph}"`);
}
const cb = ex('chargeback')[0];
if (cb) {
  const prod = cb.a['data-product'], base = Number(cb.a['data-base']), bonus = Number(cb.a['data-bonus']), lead = Number(cb.a['data-leadership']), total = Number(cb.a['data-total']);
  if (base !== expected['commission-supervisor'][prod] || bonus !== expected['bonus-25-49'][prod] || lead !== rate) errors.push('chargeback example components do not match V1');
  if (total !== base + bonus + lead || Number(cb.a['data-reversal']) !== -total) errors.push('chargeback totals inconsistent');
  for (const ph of [`${$(base)} + ${$(bonus)} + ${$(lead)} = ${$(total)}`, `-${$(total)}`, '100%', '3 meses', 'compensarse contra comisiones futuras']) if (!cb.text.includes(ph)) errors.push(`chargeback: missing "${ph}"`);
  if (!/al menos tres meses/.test(md) || !/100% de la comisión base/.test(md)) errors.push('V1 doc chargeback wording changed — review chargeback example');
  // one receipt table: concept | generated | reversed (100%)
  const rc = (cb.body.match(/<table class="receipt"[^>]*>([\s\S]*?)<\/table>/) || [, ''])[1];
  const rows = (blk) => [...blk.matchAll(/<tr><th scope="row">([^<]*)<\/th><td>([^<]*)<\/td><td class="rv">([^<]*)<\/td><\/tr>/g)].map((m) => [decode(m[1]), decode(m[2]), decode(m[3])]);
  const body = rows((rc.match(/<tbody>([\s\S]*?)<\/tbody>/) || [, ''])[1]);
  const foot = rows((rc.match(/<tfoot>([\s\S]*?)<\/tfoot>/) || [, ''])[1]);
  const wantBody = [['Comisión base Supervisor', $(base), `-${$(base)}`], ['Bono de Producción', $(bonus), `-${$(bonus)}`], ['Bono de Liderazgo relacionado', $(lead), `-${$(lead)}`]];
  const wantFoot = [['Total', $(total), `-${$(total)}`]];
  if (JSON.stringify(body) !== JSON.stringify(wantBody)) errors.push('chargeback: receipt rows differ from V1-derived values (100% reversal)');
  if (JSON.stringify(foot) !== JSON.stringify(wantFoot)) errors.push('chargeback: receipt total differs from V1-derived values');
  if (!/<ul class="rev|<table class="receipt"/.test(cb.body) || /class="rev pos"/.test(cb.body)) errors.push('chargeback: expected the single receipt table');
  if (!cb.text.includes(`${$(base)} + ${$(bonus)} + ${$(lead)} = ${$(total)}`)) errors.push('chargeback: sum formula missing');
}
const mt = ex('maintenance')[0];
const maintTarget = Number((md.match(/(\d+) conexiones válidas por trimestre/) || [])[1]);
if (mt) {
  const personal = Number(mt.a['data-personal']), base = Number(mt.a['data-base']), total = Number(mt.a['data-total']);
  if (personal + base !== total || total !== maintTarget) errors.push(`maintenance: ${personal} + ${base} != ${total} (V1 ${maintTarget})`);
  if (!mt.text.includes(`${personal} + ${base} = ${total}`)) errors.push('maintenance: formula text missing');
  if (!mt.text.includes('Meta de mantenimiento cumplida')) errors.push('maintenance: result text missing');
}

// Owner decision: the 25/50 accumulation period is NOT defined yet -> examples must stay period-neutral.
const noPeriod = /\b(del mes|mensual\w*|este mes|durante el mes|al mes|cada mes|por trimestre|trimestral\w*|anual\w*)\b/i;
const bonoSection = plain((html.match(/<section id="bono"[\s\S]*?<\/section>/) || [''])[0]);
if (!bonoSection) errors.push('bono section not found');
if (noPeriod.test(bonoSection)) errors.push(`25/50 section must not assign a period: "${(bonoSection.match(noPeriod) || [])[0]}"`);
for (const k of ['bonus-25', 'bonus-50', 'bonus-spectrum']) { const e = ex(k)[0]; if (e && noPeriod.test(e.text)) errors.push(`${k}: must not assign a period`); }
// Owner decision: no consequence for missing the 150 maintenance target is defined -> must not be invented.
const consequence = /(pierd\w*|perder|baja a |bajar|descen\w+|gracia|retien\w+|retenci\w+|suspend\w+|penaliz\w+|sanci\w+|consecuenci\w+)/i;
const maintSection = plain((html.match(/<section id="mantenimiento"[\s\S]*?<\/section>/) || [''])[0]);
if (!maintSection) errors.push('mantenimiento section not found');
if (consequence.test(maintSection)) errors.push(`maintenance must not state a consequence: "${(maintSection.match(consequence) || [])[0]}"`);

// Icon system + accessibility
for (const id of ['agent', 'training', 'promotion', 'supervisor', 'team', 'home', 'router', 'fiber', 'check', 'money', 'bonus', 'leadership', 'network', 'goal', 'shield', 'reversal', 'calendar', 'x', 'ban']) {
  if (!html.includes(`<symbol id="i-${id}"`)) errors.push(`icon sprite missing symbol: ${id}`);
}
const icSvgs = [...html.matchAll(/<svg class="ic[^"]*"([^>]*)>/g)];
if (icSvgs.length < 20) errors.push(`expected many icon uses, found ${icSvgs.length}`);
for (const m of icSvgs) if (!/aria-hidden="true"/.test(m[1])) errors.push('decorative icon without aria-hidden="true"');
if (!/<svg[^>]*aria-hidden="true"[^>]*><defs>/.test(html)) errors.push('icon sprite must be aria-hidden');
if (/\p{Extended_Pictographic}/u.test(plain(visible))) errors.push('emoji found in visible text (use SVG icons)');


// ── Beginner-first teaching rules (owner order: concept -> example -> calculation -> result) ──
const sectionHtml = (id) => (html.match(new RegExp(`<section id="${id}"[\\s\\S]*?</section>`)) || [''])[0];
const sectionText = (id) => plain(sectionHtml(id));
const at = (needle) => html.indexOf(needle);
const mustPrecede = [
  ['glossary before the first calculation', 'id="glosario"', 'data-ej="level-training"'],
  ['María story: Entrenamiento -> Asociado', 'data-ej="level-training"', 'data-ej="level-associate"'],
  ['María story: Asociado -> Supervisor', 'data-ej="level-associate"', 'data-ej="level-supervisor"'],
  ['base commission before bonuses', 'data-ej="level-supervisor"', 'id="fuentes"'],
  ['full tables only after the three levels', 'data-ej="level-supervisor"', 'id="tablas"'],
  ['pool explained before any bonus example', 'id="pool"', 'data-ej="bonus-25"'],
  ['tramos explained before the 25–49 example', 'class="tramos"', 'data-ej="bonus-25"'],
  ['25 before 50', 'data-ej="bonus-25"', 'data-ej="bonus-50"'],
  ['production bonus before leadership', 'data-ej="bonus-50"', 'data-ej="leadership"'],
  ['leadership story before its example', 'data-story="true"', 'data-ej="leadership"'],
  ['simple leadership before advanced scenario', 'data-ej="leadership"', 'class="scens"'],
  ['chargeback explained before the numbers', 'data-explain="chargeback"', 'data-ej="chargeback"'],
  ['maintenance explained before its example', 'La referencia de mantenimiento es 150', 'data-ej="maintenance"'],
];
for (const [label, a1, b1] of mustPrecede) { const x = at(a1), y = at(b1); if (x < 0 || y < 0 || x > y) errors.push(`teaching order: ${label}`); }
{
  const pt = plain(visible);
  const gloIdx = pt.indexOf('Palabras que debes conocer');
  if (gloIdx < 0) errors.push('glossary heading missing');
  for (const w of [/\bpool\b/i, /chargeback/i, /base elegible|base directa/i, /bono de producci[oó]n/i, /mantenimiento/i]) { const i2 = pt.search(w); if (i2 >= 0 && i2 < gloIdx) errors.push(`term ${w} used before the glossary`); }
}
const gloss = { 'conexion-valida': 'Una conexión que cumple los requisitos del plan para generar compensación.', 'comision-base': 'La cantidad correspondiente al producto y a tu nivel.', pool: 'Las conexiones válidas que cuentan para medir la producción del Supervisor según las reglas del plan.', 'bono-produccion': 'Compensación adicional que comienza al entrar en los tramos correspondientes.', 'bono-liderazgo': `$${rate} por conexión válida elegible de Internet según la estructura de liderazgo V1.`, chargeback: 'Reversión de compensación relacionada con una conexión que no cumple el mínimo requerido de permanencia.' };
for (const [k, def] of Object.entries(gloss)) {
  const m = html.match(new RegExp(`<div class="g" data-term="${k}">([\\s\\S]*?)</div>`));
  if (!m) { errors.push(`glossary term missing: ${k}`); continue; }
  if (!plain(m[1]).includes(def)) errors.push(`glossary definition differs for ${k}`);
}
for (const k of ['base-directa', 'mantenimiento', 'producto', 'tramo', 'desarrollar']) if (!html.includes(`data-term="${k}"`)) errors.push(`glossary term missing: ${k}`);
if (![...html.matchAll(/data-term="/g)].length || [...html.matchAll(/<div class="g" data-term=/g)].length !== 11) errors.push(`glossary should have 11 terms, found ${[...html.matchAll(/<div class="g" data-term=/g)].length}`);
// plain-language support for jargon a new agent would not know
for (const [what, where, ph] of [['BYOD', 'producto', 'el cliente trae su propio dispositivo'], ['Mbps/Gig', 'producto', 'indican su velocidad'], ['tramo', 'tramo', 'de la 25 a la 49'], ['desarrollar', 'desarrollar', 'tu agente directo']]) { const m = html.match(new RegExp(`<div class="g" data-term="${where}">([\\s\\S]*?)</div>`)); if (!m || !plain(m[1]).includes(ph)) errors.push(`glossary must explain ${what}`); }
// every internal link must land on a real element
for (const m of html.matchAll(/href="#([^"]+)"/g)) if (!html.includes(`id="${m[1]}"`)) errors.push(`broken internal link: #${m[1]}`);

// Each level follows the 7 steps in order
const stepsOrder = ['¿Dónde estoy?', '¿Qué tengo que hacer?', '¿Cuánto paga?', 'Ejemplo real', '¿Cómo se calcula?', '¿Cuánto ganaría en este ejemplo?', '¿Cómo avanzo'];
for (const id of ['nivel-1', 'nivel-2', 'nivel-3']) {
  const sh = sectionHtml(id); let last = -1;
  for (const st of stepsOrder) { const i2 = sh.indexOf(st); if (i2 < 0 || i2 < last) errors.push(`${id}: step "${st}" missing or out of order`); last = i2; }
}
{
  const n1 = sectionText('nivel-1'), n2 = sectionText('nivel-2'), n3 = sectionText('nivel-3');
  for (const ph of ['Este es tu punto de partida', 'Cuando comienzas en IZZY Communications, empiezas como Agente en Entrenamiento.', 'Realizas una conexión, la conexión es validada y recibes la comisión correspondiente al producto.', 'María es nueva en IZZY Communications', 'Consulta con tu Supervisor los requisitos vigentes de ascenso.']) if (!n1.includes(ph)) errors.push(`nivel-1 missing: ${ph}`);
  const vf = [...sectionHtml('nivel-1').matchAll(/<span class="vt">([^<]+)<\/span>/g)].map((m) => m[1]);
  if (JSON.stringify(vf) !== JSON.stringify(['Tú', 'Realizas la venta', 'El cliente recibe el servicio', 'La conexión es válida', 'Recibes la comisión'])) errors.push(`nivel-1: "¿Cómo ganas?" flow differs: ${vf.join(' > ')}`);
  for (const ph of ['Ahora María avanzó a Asociado', 'El producto no cambió. Lo que cambió fue el nivel de María.', '1 AT&T 500 × $125 de comisión de Asociado = $125', 'Misma conexión', 'Nuevo nivel', 'Mayor comisión', 'Consulta con tu Supervisor los requisitos vigentes de ascenso.']) if (!n2.includes(ph)) errors.push(`nivel-2 missing: ${ph}`);
  for (const ph of ['María llegó a Supervisor', 'Ahora puedes ver por qué crecer de nivel cambia tu comisión.', 'Hasta aquí estamos hablando solamente de comisión base.', 'Mismo producto. La comisión base aumenta según el rango.']) if (!n3.includes(ph)) errors.push(`nivel-3 missing: ${ph}`);
  // promotion requirements must NOT be invented: the "¿Cómo avanzo" block of levels 1–2 carries no numbers
  for (const id of ['nivel-1', 'nivel-2']) { const blk = sectionHtml(id).split('¿Cómo avanzo')[1] || ''; if (/\d/.test(plain(blk))) errors.push(`${id}: promotion block must not state numeric requirements`); }
}
{
  const pl = sectionText('pool');
  for (const ph of ['Tu pool es el grupo de conexiones válidas que cuentan para medir tu producción como Supervisor, de acuerdo con las reglas del plan.', 'Tu producción personal', 'Producción elegible de tu base directa', 'Tu pool']) if (!pl.includes(ph)) errors.push(`pool section missing: ${ph}`);
  if (!sectionHtml('pool').includes('data-pool-formula="true"')) errors.push('pool formula visual missing');
}
{
  const bn = sectionText('bono');
  for (const ph of ['Comisión normal', 'llegas a la #25', 'llegas a la #50', 'Los bonos no regresan hacia atrás para recalcular conexiones anteriores.', 'NO son retroactivos']) if (!bn.includes(ph)) errors.push(`bono section missing: ${ph}`);
  if (/\bpool\b/i.test(sectionText('fuentes'))) errors.push('fuentes (bonus intro) must not use the word pool before it is explained');
}
{
  const ls = sectionText('liderazgo');
  for (const ph of ['aparece cuando desarrollas a una persona y esa persona llega a Supervisor', 'María ayudó a Carlos a desarrollarse. Carlos llegó a Supervisor.', 'Quién lo genera', 'Quién lo recibe', 'solo sobre conexiones de Internet', 'Un escenario más avanzado']) if (!ls.includes(ph)) errors.push(`liderazgo section missing: ${ph}`);
  if (!sectionHtml('liderazgo').includes('data-leadership="eligible"')) errors.push('liderazgo: eligible products missing');
}
{
  const ch = sectionText('chargeback');
  for (const ph of ['Para conservar la comisión, la cuenta debe mantenerse activa por un mínimo de 3 meses.', 'Si la conexión cae antes de cumplir ese mínimo, los pagos relacionados con esa conexión pueden revertirse según las reglas del plan.', 'A eso se le llama chargeback', 'cuidar que tus cuentas permanezcan activas']) if (!ch.includes(ph)) errors.push(`chargeback section missing: ${ph}`);
  if (sectionHtml('chargeback').indexOf('Para conservar la comisión') > sectionHtml('chargeback').indexOf('-$150')) errors.push('chargeback: explanation must come before the negative numbers');
}
{
  const mt2 = sectionText('mantenimiento');
  for (const ph of ['¿Qué necesita un Supervisor para mantener su producción?', 'La referencia de mantenimiento es 150 conexiones válidas por trimestre, contando producción personal y base directa elegible según las reglas V1.', 'En este ejemplo se alcanza la meta de mantenimiento.']) if (!mt2.includes(ph)) errors.push(`mantenimiento missing: ${ph}`);
}
// "Prueba del agente nuevo": the 13 questions must be answerable from the page text
const newcomer = [
  ['1. ¿En qué nivel comienzo?', 'nivel-1', 'empiezas como Agente en Entrenamiento'],
  ['2. ¿Cómo genero una comisión?', 'nivel-1', 'Realizas una conexión, la conexión es validada y recibes la comisión'],
  ['3. ¿Cuánto paga el ejemplo?', 'nivel-1', 'María genera $100 de comisión base'],
  ['4. ¿Por qué cambia mi comisión al ascender?', 'nivel-2', 'Lo que cambió fue el nivel de María'],
  ['5. ¿Qué significa pool?', 'pool', 'Tu pool es el grupo de conexiones válidas'],
  ['6. ¿Qué ocurre al llegar a la #25?', 'bono', 'Al lograr la conexión #25 entras al tramo 25–49'],
  ['7. ¿Qué cambia desde la #50?', 'bono', 'Al lograr la conexión #50 pasas al tramo 50+'],
  ['8. ¿Qué es el Bono de Liderazgo?', 'liderazgo', 'aparece cuando desarrollas a una persona y esa persona llega a Supervisor'],
  ['9. ¿Quién genera ese bono?', 'liderazgo', 'Quién lo genera'],
  ['10. ¿Por qué BYOD no genera liderazgo?', 'liderazgo', 'solo sobre conexiones de Internet'],
  ['11. ¿Qué significa chargeback?', 'chargeback', 'A eso se le llama chargeback'],
  ['12. ¿Por qué importan los 3 meses?', 'chargeback', 'Para conservar la comisión, la cuenta debe mantenerse activa por un mínimo de 3 meses'],
  ['13. ¿Qué significa la meta de 150?', 'mantenimiento', 'La referencia de mantenimiento es 150 conexiones válidas por trimestre'],
];
for (const [q, id, ans] of newcomer) if (!sectionText(id).includes(ans)) errors.push(`newcomer test failed — ${q} (not answered in #${id})`);


// ── Visual pass: 10-second level snapshot, staircase, scan strips, progressive disclosure ──
{
  const prod = 'AT&T 500 Mbps';
  const lv = { training: 'Agente en Entrenamiento', associate: 'Asociado', supervisor: 'Supervisor' };
  const amt = (l) => expected[`commission-${l}`][prod];
  for (const l of Object.keys(lv)) {
    const m = html.match(new RegExp(`<div class="snap" data-snap="${l}"([^>]*)>([\\s\\S]*?)</div>\\s*(?=<div class="qb">)`));
    if (!m) { errors.push(`snapshot missing for ${l}`); continue; }
    const a = attrsOf(m[1]), tx = plain(m[2]);
    if (a['data-product'] !== prod || Number(a['data-amount']) !== amt(l)) errors.push(`snapshot ${l}: ${a['data-product']} ${a['data-amount']} != V1 ${amt(l)}`);
    if (!tx.includes(lv[l]) || !tx.includes(prod) || !tx.includes(`$${amt(l)}`)) errors.push(`snapshot ${l}: must show level, product and amount`);
  }
  const lvlEx = [...html.matchAll(/<p class="lvl-ex" data-amount="(\d+)"><span>([^<]*)<\/span><b>\$(\d+)<\/b>/g)].map((m) => [Number(m[1]), decode(m[2]), Number(m[3])]);
  if (JSON.stringify(lvlEx) !== JSON.stringify(['training', 'associate', 'supervisor'].map((l) => [amt(l), prod, amt(l)]))) errors.push('camino level cards must show AT&T 500 Mbps and the V1 amount');
  const bars = [...html.matchAll(/<li class="sb[^"]*" data-level="(\w+)" data-amount="(\d+)"( data-diff="(\d+)")?>/g)].map((m) => [m[1], Number(m[2]), m[4] ? Number(m[4]) : null]);
  if (JSON.stringify(bars.map((b) => b[0])) !== JSON.stringify(['training', 'associate', 'supervisor'])) errors.push('stairs must show training, associate, supervisor');
  bars.forEach(([l, a, d], i) => { if (a !== amt(l)) errors.push(`stairs ${l}: ${a} != V1`); if (i > 0 && d !== a - bars[i - 1][1]) errors.push(`stairs ${l}: diff ${d} != ${a - bars[i - 1][1]}`); });
  const hts = [...html.matchAll(/class="sb-bar" style="height:(\d+)px"/g)].map((m) => Number(m[1]));
  if (hts.length !== 3 || !(hts[0] < hts[1] && hts[1] < hts[2])) errors.push('stairs bars must rise');
  if (hts.length === 3 && [1, 2].some((i) => Math.abs(hts[i] / hts[0] - bars[i][1] / bars[0][1]) > 0.02)) errors.push('stairs bar heights must be proportional to the amounts (all three bars)');
  const scan = (k) => { const m = html.match(new RegExp(`<div class="scan" data-scan="${k}"([^>]*)>([\\s\\S]*?)</div>\\s*(?=\\n)`)); return m ? { a: attrsOf(m[1]), tx: plain(m[2]), raw: m[2] } : null; };
  const sb = scan('bono');
  if (!sb) errors.push('scan strip missing: bono'); else {
    const ns = [...sb.raw.matchAll(/data-ordinal="(\d+)" data-bonus="(\d+)"/g)].map((m) => [Number(m[1]), Number(m[2])]);
    if (JSON.stringify(ns) !== JSON.stringify([[25, expected['bonus-25-49'][prod]], [50, expected['bonus-50-plus'][prod]]])) errors.push(`scan bono numbers != V1: ${JSON.stringify(ns)}`);
    for (const [o, b2] of ns) if (!sb.tx.includes(`#${o}`) || !sb.tx.includes(`+$${b2}`)) errors.push(`scan bono: text missing #${o} +$${b2}`);
    if (!sb.tx.includes(`$${expected['commission-supervisor'][prod]}`)) errors.push('scan bono: base amount missing');
  }
  const sl = scan('leadership');
  if (!sl || Number(sl.a['data-rate']) !== rate || !sl.tx.includes(`$${rate}`)) errors.push('scan leadership must show the V1 rate');
  const sm = scan('maintenance');
  if (!sm || Number(sm.a['data-target']) !== maintTarget || !sm.tx.includes(String(maintTarget)) || !/trimestre/.test(sm.tx)) errors.push('scan maintenance must show the V1 target per trimestre');
  const sc = scan('chargeback');
  if (!sc || Number(sc.a['data-months']) !== 3 || !sc.tx.includes('3 meses') || !/al menos tres meses/.test(md)) errors.push('scan chargeback must show the 3-month minimum');
  // progressive disclosure: few accordions, and the main calculation never hides inside one
  const nDetails = (html.match(/<details\b/g) || []).length;
  if (nDetails > 6) errors.push(`too many accordions: ${nDetails} (max 6)`);
  for (const m of html.matchAll(/<details[^>]*>([\s\S]*?)<\/details>/g)) if (/data-ej="(level-|bonus-|leadership|maintenance|chargeback)/.test(m[1]) && !/ejemplo avanzado/i.test(m[1])) errors.push('a primary example is hidden inside an accordion');
  if (!/<details class="more">\s*<summary>Ver ejemplo avanzado/.test(html)) errors.push('advanced A/B/C example must live behind "Ver ejemplo avanzado"');
  if (html.indexOf('class="scens"') < html.indexOf('Ver ejemplo avanzado')) errors.push('A/B/C scenario must be inside the advanced accordion');
  // each level example is an illustrated ticket with the result as the dominant element
  for (const l of ['training', 'associate', 'supervisor']) { const e = ex(`level-${l}`)[0]; if (e && (!e.body.includes('class="tk"') || !e.body.includes('class="tk-res"') || !e.text.includes('María vende') || !e.text.includes('María genera'))) errors.push(`level-${l}: ticket (María vende -> conexión válida -> cálculo -> María genera) missing`); }
  // calm chargeback: no alarm styling
  if (/badge red|class="[^"]*\bred\b[^"]*"/.test(sectionHtml('chargeback'))) errors.push('chargeback must stay calm: no red styling');
  if (!sectionHtml('chargeback').includes('Debe permanecer mínimo 3 meses')) errors.push('chargeback timeline must say "Debe permanecer mínimo 3 meses"');
  // icon system regression guard: the duotone fill must be styled on the <symbol> content
  if (/\.ic \.t\s*\{/.test(html)) errors.push('duotone CSS must not target ".ic .t" (does not reach <symbol> content)');
  if (!/symbol \.t\s*\{[^}]*fill:var\(--tone/.test(html)) errors.push('duotone fill rule missing (symbol .t)');
  const symBodies = [...html.matchAll(/<symbol id="i-([a-z]+)"[^>]*>([\s\S]*?)<\/symbol>/g)];
  if (symBodies.length !== 22) errors.push(`expected 22 icons, found ${symBodies.length}`);
  for (const [, id2, body] of symBodies) { const strokeWidth = (html.match(new RegExp(`<symbol id="i-${id2}"[^>]*stroke-width="([\\d.]+)"`)) || [])[1]; if (strokeWidth !== '1.8') errors.push(`icon ${id2}: stroke-width ${strokeWidth} != 1.8`); if (body.length > 420) errors.push(`icon ${id2}: too complex (${body.length} chars)`); }
}
console.log(`products=${products} commissions=${commissions} bonuses=${bonuses} (expected 10 / 30 / 20)`);
if (products !== 10 || commissions !== 30 || bonuses !== 20) errors.push('count mismatch');
if (errors.length) { console.error('PUBLIC TUTORIAL VALIDATION FAILED'); errors.forEach((e) => console.error('  -', e)); }
if (legacyHits.length) console.error('LEGACY CONTENT FOUND:', legacyHits.join(', '));
if (confHits.length) console.error('CONFIDENTIAL TERMS FOUND:', confHits.join(', '));
if (errors.length || legacyHits.length || confHits.length) process.exit(1);
console.log('OK: economics match V1; no legacy or confidential terms.');
