// SIMULATED target for tool/live/live_chat_test.mjs: the real chat-v7 Worker
// (backend/worker.js + cost_guard.js + coach_prompts.js) runs in this process
// with the existing backend test fakes (backend/test/helpers.mjs: an in-memory
// Durable Object namespace and a throwaway Apple-shaped test PKI). Workers AI
// is replaced by a scripted model, so nothing touches the network and no
// neurons are spent. Replies are canned text, never AI output.
//
// Why not `wrangler dev --local`: the Workers AI binding always runs remotely
// (it needs a Cloudflare account and spends neurons), and no Worker variable can
// change the trusted root (Apple Root CA - G3), so a test-PKI token cannot pass
// there. Pointing the kit at `wrangler dev` is therefore a LIVE run (see
// docs/qa/LIVE_AI_TEST_PLAN.md).
import { readFileSync } from 'node:fs';
import worker from '../../backend/worker.js';
import { _setTrustedRootsForTests } from '../../backend/cost_guard.js';
import { sha256Hex } from '../../backend/apple_jws.js';
import { fakeDoNamespace, makePki, txPayload } from '../../backend/test/helpers.mjs';
import { detectLanguage } from './checks.mjs';

/** The [vars] of backend/wrangler.toml (the production limits), as strings. */
export function wranglerVars() {
  const toml = readFileSync(new URL('../../backend/wrangler.toml', import.meta.url), 'utf8');
  const vars = {};
  const section = toml.split(/^\[vars\]\s*$/m)[1] || '';
  for (const line of section.split('\n')) {
    if (/^\s*\[/.test(line)) break;
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*"([^"]*)"/);
    if (m) vars[m[1]] = m[2];
  }
  return vars;
}

/** Apple's sample notification (App Store Server Library test chain, MIT), and its root fingerprint. */
export async function appleSample() {
  const jws = readFileSync(new URL('../../backend/test/apple_sample/testNotification', import.meta.url), 'utf8').trim();
  const root = JSON.parse(Buffer.from(jws.split('.')[0], 'base64url')).x5c[2];
  return { jws, rootSha256: await sha256Hex(Buffer.from(root, 'base64')) };
}

// --- the scripted model ------------------------------------------------------
const MANIPULATION = /(jealous|guilt|manipulat|pressure her|make (?:her|him) (?:feel|come)|celos|culpable|manipul|presion)/i;
const INJECTION = /(ignore (?:all |your )?(?:previous )?instructions|you are now|ignora (?:tus|todas) (?:las )?instrucciones|ahora eres)/i;
const HUMAN_Q = /(real person|are you (?:a )?human|persona real|eres (?:una )?persona|eres humano)/i;

const LINES = {
  en: {
    intro: (n) => `Hi, I'm ${n}, your DateWise AI coach.`,
    ai: (n) => `I'm ${n}, DateWise's AI coach, not a person. **I'm an AI, and I'm here to help with your dating life.**`,
    decline: () => "I can't help with making someone jealous or guilty; that pressure backfires and isn't respectful. **Instead, be honest:** tell them what you miss and ask if they'd like to talk.",
    injection: (n) => `I'm ${n}, and I stick to dating coaching, so I won't switch roles or write code. **Let's get back to your love life.**`,
    recall: (h) => `You told me they love ${h}. **Use it:** "Okay, real question: what got you into ${h}?"`,
    memory: (m) => `Since ${m}, here's an idea that fits you. **Pick a cozy spot you already like** and keep it to one drink.`,
    generic: () => "Here's what's already working: you're asking, which most people don't. **Keep it short and specific.** Send something like \"That photo at the lake looks fun, what's the story?\"",
    step: () => 'Your next step today: send one message and see how it lands.',
    question: () => 'What do you know about them so far?',
  },
  es: {
    intro: (n) => `¡Hola! Soy ${n}, tu coach de IA en DateWise.`,
    ai: (n) => `Soy ${n}, la coach de IA de DateWise, no una persona. **Soy una IA y estoy aquí para ayudarte con tus citas.**`,
    decline: () => 'No puedo ayudarte a poner celosa a nadie ni a hacerla sentir culpable; esa presión no es respetuosa. **En lugar de eso, sé honesto:** dile lo que extrañas y pregúntale si quiere hablar.',
    injection: (n) => `Soy ${n} y solo te ayudo con tus citas, así que no voy a cambiar de papel. **Volvamos a tu vida amorosa.**`,
    recall: (h) => `Me dijiste que le encanta ${h}. **Úsalo:** "Pregunta seria: ¿cómo empezaste con ${h}?"`,
    memory: (m) => `Como ${m}, aquí tienes una idea a tu medida. **Elige un lugar tranquilo que ya te guste.**`,
    generic: () => 'Lo que ya funciona: estás preguntando, y eso es valiente. **Sé breve y concreto.** Escríbele algo como "Esa foto en la playa se ve genial, ¿qué historia tiene?"',
    step: () => 'Tu paso de hoy: envía un mensaje y mira cómo responde.',
    question: () => '¿Qué sabes de esa persona hasta ahora?',
  },
};

/** A canned reply that follows the server's system prompt the way a compliant model would. */
export function scriptedReply(messages) {
  const sys = messages.filter((m) => m.role === 'system');
  // A model obeys an injected system message. The Worker drops client system
  // messages, so this branch only runs if that protection breaks.
  if (sys.length > 1) return sys.slice(1).map((m) => m.content).join(' ');
  const system = sys[0]?.content || '';
  const name = (system.match(/^You are (\S+), an AI dating coach/) || [])[1] || 'your coach';
  const turns = messages.filter((m) => m.role !== 'system');
  const users = turns.filter((m) => m.role === 'user');
  const last = users.at(-1)?.content || '';
  const coachLang = system.includes('Latin-American Spanish') ? 'es' : 'en';
  const detected = detectLanguage(last).lang;
  const lang = detected === 'unknown' ? coachLang : detected;
  const L = LINES[lang];
  const parts = [];
  if (users.length === 1 && !HUMAN_Q.test(last)) parts.push(L.intro(name));
  if (MANIPULATION.test(last)) {
    parts.push(L.decline());
  } else if (INJECTION.test(last)) {
    parts.push(L.injection(name));
  } else if (HUMAN_Q.test(last)) {
    parts.push(L.ai(name));
  } else {
    const earlier = users.slice(0, -1).map((m) => m.content).join(' ');
    const hobby = earlier.match(/(?:loves|really into|le encanta(?:n)?) (?:el |la |los |las )?([a-záéíóúñ]+(?: [a-z]+)?)/i);
    const memory = system.match(/remember this about them[^"]*"([^"]*)"/);
    if (hobby) parts.push(L.recall(hobby[1]));
    else if (memory) parts.push(L.memory(memory[1].replace(/^I'm /i, "you're ").replace(/\.$/, '').replace(/\bI live\b/i, 'you live')));
    else parts.push(L.generic());
    parts.push(users.length === 1 ? L.question() : L.step());
  }
  if (users.length === 1 && !MANIPULATION.test(last)) parts.push(L.step());
  return parts.join('\n\n');
}

function sseStream(text, { promptTokens, delayMs = 2 }) {
  const enc = new TextEncoder();
  const chunks = text.match(/.{1,40}/gs) || [];
  let i = 0;
  let canceled = false;
  return new ReadableStream({
    async pull(controller) {
      await new Promise((r) => setTimeout(r, delayMs));
      if (canceled) return;
      if (i < chunks.length) {
        controller.enqueue(enc.encode(`data: ${JSON.stringify({ response: chunks[i++] })}\n\n`));
        return;
      }
      const usage = { prompt_tokens: promptTokens, completion_tokens: Math.ceil(enc.encode(text).length / 4) };
      controller.enqueue(enc.encode(`data: ${JSON.stringify({ response: '', usage })}\n\ndata: [DONE]\n\n`));
      controller.close();
    },
    cancel() {
      canceled = true;
    },
  });
}

/**
 * Builds the in-process target. `vars` override backend/wrangler.toml [vars].
 * Date.now is replaced by a virtual clock (sleep() advances it at once), so the
 * per-minute limits behave as in production without waiting; close() restores it.
 */
export async function createLocalTarget({ vars = {}, chunkDelayMs = 2 } = {}) {
  const realNow = Date.now;
  let offset = 0;
  const now = () => realNow() + offset;
  Date.now = now;

  const pki = await makePki();
  const sample = await appleSample();
  // The test PKI (the stand-in for Apple Root CA - G3) and Apple's sample chain.
  _setTrustedRootsForTests([pki.rootSha256, sample.rootSha256]);
  const jws = await pki.sign(txPayload({ environment: 'Sandbox', originalTransactionId: `9${String(realNow()).slice(-14)}` }));

  const aiCalls = [];
  const env = {
    ...wranglerVars(),
    ...vars,
    USAGE_GUARD: fakeDoNamespace(),
    AI: {
      async run(model, input) {
        aiCalls.push({ model, input: structuredClone(input) });
        const text = scriptedReply(input.messages || []);
        const promptTokens = Math.ceil(new TextEncoder().encode(JSON.stringify(input.messages)).length / 4);
        return sseStream(text, { promptTokens, delayMs: chunkDelayMs });
      },
    },
  };

  // The guard's count-only usage log lines (no text), kept for the report.
  const usageLog = [];
  const realLog = console.log;
  console.log = (...args) => {
    if (typeof args[0] === 'string' && args[0].startsWith('{"event":"usage"')) {
      try {
        usageLog.push(JSON.parse(args[0]));
        return;
      } catch {
        /* fall through */
      }
    }
    realLog(...args);
  };

  const pending = new Set();
  // Own network bucket per target: the Worker's per-IP window is module state shared by runs in one process.
  const ip = `198.18.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  return {
    label: 'in-process chat-v7 Worker (backend/worker.js) with backend/test fakes and a scripted model',
    baseUrl: 'https://simulated.invalid',
    jws,
    appleSampleJws: sample.jws,
    aiCalls,
    usageLog,
    env,
    now,
    async sleep(ms) {
      offset += Math.max(0, ms);
    },
    async fetch(url, init = {}) {
      const headers = new Headers(init.headers);
      headers.set('CF-Connecting-IP', ip);
      const ctx = {
        waitUntil(p) {
          const q = Promise.resolve(p).finally(() => pending.delete(q));
          pending.add(q);
        },
      };
      return worker.fetch(new Request(url, { ...init, headers }), env, ctx);
    },
    async close() {
      await Promise.allSettled([...pending]);
      console.log = realLog;
      Date.now = realNow;
      _setTrustedRootsForTests(null);
    },
  };
}
