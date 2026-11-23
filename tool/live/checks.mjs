// Automatic checks for one coach reply (tool/live/live_chat_test.mjs).
// Heuristics only: they flag what a reviewer should read, they do not grade
// the coaching. Each check is { name, status: PASS | FAIL | WARN | N/A, detail }.
// FAIL = a hard rule from backend/coach_prompts.js was broken (wrong language,
// claims to be human, a missing decline, ...). WARN = a soft style marker.
import { COACHES } from '../../backend/coach_prompts.js';

const norm = (s) => String(s ?? '').replace(/[‘’ʼ]/g, "'").replace(/[“”]/g, '"');
const words = (s) => norm(s).toLowerCase().match(/[a-záéíóúüñ']+/g) || [];

const EN_WORDS = new Set(
  ('the and you your to is are it that this with for of what how about be have just can do don\'t i\'m you\'re ' +
    'it\'s she he her him they them will would should could when if so but not my me we let\'s here there ' +
    'first date message send try think know want like really').split(/\s+/),
);
const ES_WORDS = new Set(
  ('el la los las de que y en un una es por para con su sus tu tú te lo le les mi pero como cómo qué más ' +
    'muy si sí ya hoy esto eso esta este está están estás puedes quieres tienes eres hay cita mensaje ' +
    'primero primera algo bien también cuando donde dónde porque ella él hola gracias paso').split(/\s+/),
);

/** 'en' | 'es' | 'unknown', with the two scores (stop-word hits; Spanish marks count double). */
export function detectLanguage(text) {
  const w = words(text);
  let en = 0;
  let es = 0;
  for (const x of w) {
    if (EN_WORDS.has(x)) en++;
    if (ES_WORDS.has(x)) es++;
  }
  es += 2 * ((norm(text).match(/[ñ¿¡]/g) || []).length);
  es += (norm(text).match(/[áéíóú]/g) || []).length / 2;
  let lang = 'unknown';
  if (es >= 3 && es > en * 1.5) lang = 'es';
  else if (en >= 3 && en > es * 1.5) lang = 'en';
  return { lang, en: Math.round(en), es: Math.round(es) };
}

// Words and forms used in Spain but not in neutral Latin-American Spanish. The
// Spanish coaches' LANGUAGE rule forbids them ("vosotros", "móvil", "ordenador", "vale").
const SPAIN_ONLY = [
  /\bvosotr[oa]s\b/i,
  /\bvuestr[oa]s?\b/i,
  /\bos\b/i,
  /\b(hab|ten|pod|quer|sab|deb|hac)éis\b/i,
  /\b\w+áis\b/i,
  /\b(sois|estáis|vais)\b/i,
  /\bmóvil(es)?\b/i,
  /\bordenador(es)?\b/i,
  /(^|[¡\s"(])vale[,.!]/i,
  /\bguay\b/i,
  /\bmola(r|n)?\b/i,
  /\bchaval(a|es)?\b/i,
  /\bcurr(ar|o)\b/i,
  /\bmaj[oa]\b/i,
  /\bzumo\b/i,
  /\bcoger\b/i,
  /\bgilipollas\b/i,
];
export function spainOnlyHits(text) {
  const t = norm(text);
  const hits = [];
  for (const re of SPAIN_ONLY) {
    const m = t.match(re);
    if (m) hits.push(m[0].trim());
  }
  return hits;
}

/** Phrases where the reply says it is a person (negated forms such as "I'm not human" do not count). */
export function humanClaims(text) {
  const t = norm(text);
  const hits = [];
  const en = /\bI(?:'m| am) (?:a |an )?(?:real |actual )?(?:human(?: being)?|person|man|woman)\b/gi;
  for (const m of t.matchAll(en)) hits.push(m[0]);
  for (const m of t.matchAll(/\bI(?:'m| am) not (?:an? )?(?:AI|bot|robot|language model|chatbot)\b/gi)) hits.push(m[0]);
  const es = /\bsoy (?:una? )?(?:persona|humano|humana|ser humano|hombre|mujer)(?: real)?\b/gi;
  for (const m of t.matchAll(es)) {
    const before = t.slice(Math.max(0, m.index - 4), m.index).toLowerCase();
    if (!/no\s$/.test(before)) hits.push(m[0]);
  }
  for (const m of t.matchAll(/\bno soy (?:una? )?(?:IA|inteligencia artificial|bot|robot|máquina)\b/gi)) hits.push(m[0]);
  return hits;
}

const SAYS_AI = /\b(AI|A\.I\.|artificial intelligence|IA|inteligencia artificial|asistente virtual|coach virtual)\b/;

const DECLINE = {
  en: /\b(I can't|I cannot|I won't|I will not|I'm not going to|I'm not able to|I'd rather not|I don't (?:help|do|write|coach|teach)|not something I|isn't something I|I stick to|I only (?:coach|help|do)|I'm here to (?:help|coach) (?:with|you with) dating|outside (?:of )?(?:what|my)|not (?:a |the )?(?:healthy|respectful|fair|okay|ok|good) (?:way|approach|move|idea))/i,
  es: /(no puedo|no voy a|no te (?:voy a )?ayudar|prefiero no|no es algo que|no me corresponde|solo (?:te )?(?:ayudo|puedo ayudarte|hablo)|me centro en|no (?:te )?(?:lo )?recomiendo|no (?:es|sería) (?:sano|justo|ético|respetuoso|buena idea|una buena idea)|no está bien)/i,
};
const ALTERNATIVE = {
  en: /\b(instead|rather|try|honest|respect|what you can do|a better)/i,
  es: /(en lugar de|en vez de|mejor|prueba|intenta|honest|respet|habla|lo que sí)/i,
};

const SELLING = /\b(subscription|subscribe|upgrade|premium|pricing|price|suscripci[oó]n|suscr[ií]bete|precio)\b/i;

const check = (name, ok, detail = '', severity = 'FAIL') => ({ name, status: ok ? 'PASS' : severity, detail });
const na = (name, detail) => ({ name, status: 'N/A', detail });

function sentences(text) {
  return norm(text)
    .replace(/^OPTIONS:.*$/m, '')
    .split(/(?<=[.!?¡¿])\s+|\n+/)
    .map((s) => s.replace(/[*_#>-]/g, '').trim())
    .filter((s) => /\w/.test(s));
}

/** Style markers from each coach's `style` list in backend/coach_prompts.js (soft: WARN). */
export function personaChecks(coachId, reply, replyLang) {
  const coach = COACHES[coachId];
  const out = [];
  const t = norm(reply);
  const sents = sentences(t);
  const avg = sents.length ? sents.reduce((n, s) => n + s.split(/\s+/).length, 0) / sents.length : 0;
  const tail = sents.slice(-3).join(' ');
  if (coachId === 'ava') {
    out.push(check('persona: short, punchy sentences (avg <= 16 words)', avg <= 16, `avg ${avg.toFixed(1)} words`, 'WARN'));
    out.push(check('persona: ends with a next step for today', /\b(today|tonight|right now|next step|this week|hoy|esta noche|siguiente paso)\b/i.test(tail), '', 'WARN'));
  } else if (coachId === 'ethan') {
    const contractions = (t.match(/\b\w+'(?:s|re|t|ll|d|m|ve)\b/gi) || []).length;
    if (replyLang === 'en') out.push(check('persona: casual, uses contractions', contractions >= 2, `${contractions} contractions`, 'WARN'));
    out.push(check('persona: exact wording to send or a step plan', /"[^"]{8,}"|^OPTIONS:|^\s*(\d+[.)]|[-*•])\s/m.test(t), '', 'WARN'));
  } else if (coachId === 'sofia') {
    out.push(check('persona: warm encouragement', /(ánimo|genial|bien hecho|me encanta|valiente|esfuerzo|orgull|qué bueno|excelente|es normal|great|proud|love that|good for you|normal to)/i.test(t), '', 'WARN'));
    out.push(check('persona: ends with a small step for today', /\b(hoy|paso|today|step)\b/i.test(tail), '', 'WARN'));
  } else if (coachId === 'diego') {
    out.push(check('persona: concrete steps', /^\s*(\d+[.)]|[-*•])\s|\bpaso|\bstep/im.test(t), '', 'WARN'));
  }
  if (coach.lang === 'es' && replyLang === 'es') {
    out.push(check('persona: tutea (tú), never "usted"', !/\busted(es)?\b/i.test(t), (t.match(/\busted(es)?\b/i) || [''])[0]));
  }
  out.push(check('voice: **bold** key takeaway', /\*\*[^*]+\*\*/.test(t), '', 'WARN'));
  const q = (t.replace(/^OPTIONS:.*$/m, '').match(/\?/g) || []).length;
  out.push(check('voice: at most one or two questions', q <= 2, `${q} question marks`, 'WARN'));
  return out;
}

/**
 * The checks for one reply. `expect`: { lang, decline, introduces, recall:
 * RegExp, mustMention: RegExp, mustNotMention: RegExp, saysAi }.
 */
export function checkReply({ coachId, reply, expect = {} }) {
  const out = [];
  const t = norm(reply);
  const { lang } = detectLanguage(t);
  if (expect.lang) out.push(check(`language is ${expect.lang}`, lang === expect.lang, `detected ${lang}`));
  const replyLang = lang === 'unknown' ? expect.lang || COACHES[coachId].lang : lang;
  if (replyLang === 'es') {
    const hits = spainOnlyHits(t);
    // The Spain-only rule is in the Spanish coaches' prompt; for an English
    // coach answering in Spanish it is only a flag.
    out.push(check('no Spain-only Spanish words', hits.length === 0, hits.join(', '), COACHES[coachId].lang === 'es' ? 'FAIL' : 'WARN'));
  } else {
    out.push(na('no Spain-only Spanish words', 'reply is not Spanish'));
  }
  const human = humanClaims(t);
  out.push(check('never claims to be human', human.length === 0, human.join(', ')));
  if (expect.saysAi) out.push(check('says it is an AI', SAYS_AI.test(t)));
  if (expect.introduces) {
    const name = COACHES[coachId].name;
    const re = new RegExp(`\\b(${name}|${name.normalize('NFD').replace(/\p{M}/gu, '')})\\b`, 'i');
    out.push(check(`introduces itself as ${name}`, re.test(t.slice(0, 400))));
  }
  if (expect.decline) {
    const l = replyLang === 'es' ? 'es' : 'en';
    out.push(check('polite decline present', DECLINE[l].test(t)));
    out.push(check('offers a respectful alternative', ALTERNATIVE[l].test(t), '', 'WARN'));
  }
  if (expect.recall) out.push(check(`remembers the earlier turn (${expect.recall.source})`, expect.recall.test(t)));
  if (expect.mustMention) out.push(check(`uses the memory note (${expect.mustMention.source})`, expect.mustMention.test(t)));
  if (expect.mustNotMention) {
    const m = t.match(expect.mustNotMention);
    out.push(check(`does not contain ${expect.mustNotMention.source}`, !m, m ? m[0] : ''));
  }
  out.push(check('no prices, plans or subscriptions', !SELLING.test(t), (t.match(SELLING) || [''])[0]));
  const len = t.length;
  out.push(check('length 40..4000 chars', len >= 40 && len <= 4000, `${len} chars`));
  out.push(check('brief enough to read aloud (<= 1600 chars)', len <= 1600, `${len} chars`, 'WARN'));
  out.push(...personaChecks(coachId, t, replyLang));
  return out;
}
