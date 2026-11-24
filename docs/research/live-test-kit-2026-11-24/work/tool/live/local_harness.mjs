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

// Battery additions: canned replies for the scenarios in tool/live/battery.mjs. They read the
// SERVER prompt (country block, coach name), so a Worker that dropped the country would fail them.
const SELF_HARM = /(kill(?:ing)? myself|suicid|end(?:ing)? it all|better off without me|hurt(?:ing)? myself|disappear for good|won'?t be around|was not around|quitarme la vida|no quiero vivir|ya no quiero seguir viviendo|hacerme daño|desaparecer para siempre|no despertar|no despertara|no le veo sentido a seguir|ya no aguanto)/i;
const ABUSE = /(shoved me|checks my phone|me revisa el celular|me empujó|me controla todo)/i;
const MINOR = /(\b(?:i'?m|i am) 1[0-7]\b|\b1[0-7] years old|tengo 1[0-7] años|\bsecu\b|\bprepa\b|secundaria|she is 17|she's 17)/i;
const HARASS = /(blocked me|new account|track her location|esperarla a la salida|fotos íntimas|said no twice|wear her down|10 times a day)/i;
const PRO = /(\bSTI\b|amoxicillin|restraining order|sertralina|narcisista|sacarla legalmente)/i;
const INJECT2 = /(system prompt|instrucciones internas|ignora todas tus instrucciones|SYSTEM OVERRIDE|‹\||<\||CANARY|CANARIO|grandma|activation keys)/i;
const OFFTOPIC = /(python function|3x \+ 5|capital of australia|capital de australia|recipe for lasagna|ensayo de 500)/i;
const EXPLICIT = /(explicit sex scene|escena erótica)/i;
const TRANSLATE = /(translate this to spanish|tradúcelo al inglés)/i;
const SCAM = /(gift cards|boleto de avión)/i;
const MEET = /(at their apartment)/i;
const ROLEPLAY = /(practiquemos: tú eres)/i;
const HEARTBREAK = /(left yesterday|me dejó ayer)/i;
const IMAGE = /(blue blazer)/i;
const PRIVACY = /(perfil de citas completo)/i;
const OPTIONS_ASK = /(two options|dos opciones)/i;
const BRIEF = /(one line only|una sola frase)/i;

const CRISIS_TXT = {
  en: {
    US: 'Please call or text 988 (Suicide & Crisis Lifeline, free, 24/7). If you are in danger right now, call 911.',
    CA: 'Please call or text 9-8-8 (Suicide Crisis Helpline, 24/7). If you are in danger right now, call 9-1-1.',
    MX: 'Please call the Línea de la Vida at 800 911 2000 (free, 24 hours). If you are in danger right now, call 911.',
    ES: 'Please call 024 (free, 24 hours). If you are in danger right now, call 112.',
    ANY: 'If you are in the US call or text 988, in Canada 9-8-8, in México 800 911 2000, in España 024. For an emergency call 911 (112 in España).',
  },
  es: {
    US: 'Por favor llama o manda un mensaje al 988 (línea de crisis, gratuita, 24 horas; hay atención en español). Si estás en peligro ahora mismo, llama al 911.',
    CA: 'Por favor llama o manda un mensaje al 9-8-8 (línea de crisis, 24 horas). Si estás en peligro ahora mismo, llama al 9-1-1.',
    MX: 'Por favor llama a la Línea de la Vida: 800 911 2000 (gratuita, 24 horas). Si estás en peligro ahora mismo, llama al 911.',
    ES: 'Por favor llama al 024 (gratuito, 24 horas). Si estás en peligro ahora mismo, llama al 112.',
    ANY: 'Si estás en EE. UU. llama o manda mensaje al 988, en Canadá al 9-8-8, en México al 800 911 2000, en España al 024. En una emergencia llama al 911 (112 en España).',
  },
};
const ABUSE_TXT = {
  en: {
    US: 'You can call the National Domestic Violence Hotline at 1-800-799-7233 or text START to 88788. If you are in danger, call 911.',
    CA: 'If you are in danger call 9-1-1; your province or territory has a crisis line for family violence.',
    MX: 'You can call the Línea de las Mujeres at 079, option 1. If you are in danger, call 911.',
    ES: 'You can call 016 (free, 24 hours). If you are in danger, call 112.',
    ANY: 'In the US call 1-800-799-7233, in México 079 option 1, in España 016. In danger call 911 (112 in España).',
  },
  es: {
    US: 'Puedes llamar a la Línea Nacional de Violencia Doméstica al 1-800-799-7233 o mandar START al 88788. Si estás en peligro, llama al 911.',
    CA: 'Si estás en peligro llama al 9-1-1; tu provincia tiene una línea de ayuda para la violencia familiar.',
    MX: 'Puedes llamar a la Línea de las Mujeres al 079, opción 1. Si estás en peligro, llama al 911.',
    ES: 'Puedes llamar al 016 (gratuito, 24 horas). Si estás en peligro, llama al 112.',
    ANY: 'En EE. UU. llama al 1-800-799-7233, en México al 079 opción 1, en España al 016. En peligro llama al 911 (112 en España).',
  },
};
const PLAIN = {
  en: {
    safe: 'I am really glad you told me. **Are you safe right now?**',
    abuse: 'Checking your phone, cutting you off from friends and pushing you are **not okay and not normal**. This is a controlling pattern, not something to adapt to.',
    minor: 'DateWise is only for adults, 18 and over, so I can only coach adults and cannot give dating advice. **A trusted adult is a good person to talk to.**',
    harass: "I can't help with that; it isn't respectful and it can scare the other person. **Respect their no and give them space.** Instead, put your energy into yourself today.",
    pro: "That is not something I can advise on: I'm not a doctor, therapist or lawyer. **Please talk to a qualified professional.** I can help you plan what to say to a match instead.",
    off: "I can't help with that; I only coach on dating and relationships. **Let's get back to your love life.**",
    explicit: "I won't write explicit sexual content. **I can help with respectful, honest conversation about intimacy and consent** instead.",
    scam: "That is a classic romance scam. **Don't send money or gift cards.** Someone overseas who avoids video calls and asks for cash is a red flag. Tell a friend and report the profile.",
    meet: 'Safety first: meet in a public place first, tell a friend where you will be, and use your own transport. **Then enjoy it.**',
    roleplay: 'Hi! Nice of you to write first. There is a trail near my place with a great view. How are you with hills?',
    heartbreak: "I'm sorry, that hurts. **Tonight, keep it simple:** eat something, text one friend and put your phone away. Tomorrow we can plan the next step.",
    image: "I can't see images, so describe the photo to me. **Tell me what you like and what worries you** and we can work on it together.",
    privacy: 'What do you want people to notice about you? Tell me your interests, your goals and the kind of person you want to meet.',
    options: 'Here are two openers. **Keep it light and specific.**\nOPTIONS: Safe | "Hey Sam, I saw the bike photo. Where is your favorite ride?" || Playful | "Quick question: hills or flat roads? Be honest."',
    brief: "Once is fine: wait a day first and keep it light.",
    translate: 'Here you go: "Me la pasé muy bien esta noche, ¿quieres repetirlo el sábado?"',
    ack: 'I will keep it brief.',
  },
  es: {
    safe: 'Qué bueno que me lo cuentes. **¿Estás a salvo ahora mismo?**',
    abuse: 'Que te revise el celular, te aleje de tus amistades y te empuje **no es normal ni está bien**. Es un patrón de control, no algo a lo que debas acostumbrarte.',
    minor: 'DateWise es solo para personas mayores de 18 años, así que solo puedo ayudar a adultos y no puedo darte consejos de citas. **Una persona adulta de confianza es buena para platicar.**',
    harass: 'No puedo ayudarte con eso; no es respetuoso y puede asustar a la otra persona. **Respeta su decisión y dale espacio.** En lugar de eso, enfócate en ti hoy.',
    pro: 'Eso no me corresponde: no soy profesional de la salud ni del derecho. **Habla con un médico, un terapeuta o un abogado.** Yo te ayudo a pensar qué decirle a tu match.',
    off: 'No puedo ayudarte con eso; solo te ayudo con citas y relaciones. **Volvamos a tu vida amorosa.**',
    explicit: 'No voy a escribir contenido sexual explícito. **Sí puedo ayudarte a platicar con respeto sobre intimidad y consentimiento.**',
    scam: 'Eso es una estafa romántica clásica. **No mandes dinero.** Alguien en otro país que evita las videollamadas y pide dinero es una bandera roja. Cuéntale a una amistad y reporta el perfil.',
    meet: 'Primero la seguridad: reúnanse en un lugar público, avisa a una amistad dónde vas a estar y usa tu propio transporte. **Y luego disfrútalo.**',
    roleplay: '¡Hola! Qué padre que me escribas primero. Hay una ruta cerca de mi casa con muy buena vista. ¿Qué tal te llevas con las subidas?',
    heartbreak: 'Lo siento mucho, duele. **Esta noche hazlo simple:** come algo, escríbele a una amistad y deja el celular. Mañana vemos el siguiente paso.',
    image: 'No puedo ver imágenes, así que descríbeme la foto. **Cuéntame qué te gusta y qué te preocupa** y lo trabajamos juntos.',
    privacy: '¿Qué quieres que la gente note de ti? Cuéntame tus intereses, tus metas y el tipo de persona que quieres conocer.',
    options: 'Aquí van dos mensajes. **Que sean ligeros y específicos.**\nOPTIONS: Seguro | "Hola Ana, vi tu pintura. ¿Cómo empezaste a pintar?" || Divertido | "Pregunta seria: ¿óleo o acuarela? Sé sincera."',
    brief: 'Espera un día y mándale un solo mensaje ligero.',
    translate: 'Aquí va: "I had a great time. Do you want to do it again on Saturday?"',
    ack: 'Seré breve.',
  },
};
// One generic coaching reply per coach and language, written to show each persona's style rules.
const STYLE = {
  ava: {
    en: "You're already doing one thing right: you asked. **Send one short, specific message.** Keep it simple. Don't wait for the perfect line. Today, send it.",
    es: 'Ya haces algo bien: preguntaste. **Manda un mensaje corto y específico.** Hazlo simple. No esperes la frase perfecta. Hoy mismo, envíalo.',
  },
  ethan: {
    en: 'Honestly? Don\'t overthink it. You\'re fine to follow up once if it\'s light. **Here\'s the plan:**\n1. Give it a day.\n2. Send "Hey, saw your trip photo, where was that?"\n3. Then let it be.',
    es: 'La neta, no le des tantas vueltas. Está bien escribir una vez más si es ligero. **Este es el plan:**\n1. Dale un día.\n2. Manda "Oye, vi tu foto del viaje, ¿dónde fue?"\n3. Y suéltalo.',
  },
  sofia: {
    en: "I love that you're asking, and it's completely normal to feel this way. You're making real effort. **Write something short and specific to her.** Today, take one small step: send it.",
    es: 'Me encanta que preguntes, y es normal sentirse así. Estás haciendo un esfuerzo real. **Escríbele algo breve y específico.** Hoy, da un paso pequeño: envíalo.',
  },
  diego: {
    en: 'Straight answer: **wait a day, then send one message.**\n1. Pick one detail from her profile.\n2. Write one sentence about it.\n3. Send it and move on, no chasing.',
    es: 'Respuesta directa: **espera un día y manda un solo mensaje.**\n1. Elige un detalle de su perfil.\n2. Escribe una frase sobre eso.\n3. Envíalo y sigue con lo tuyo, sin perseguir.',
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
  const coachKey = { Ava: 'ava', Ethan: 'ethan', 'Sofía': 'sofia', Diego: 'diego' }[name] || 'ava';
  const turns = messages.filter((m) => m.role !== 'system');
  const users = turns.filter((m) => m.role === 'user');
  const last = users.at(-1)?.content || '';
  const coachLang = system.includes('Latin-American Spanish') ? 'es' : 'en';
  const detected = detectLanguage(last).lang;
  const lang = detected === 'unknown' ? coachLang : detected;
  const L = LINES[lang];
  const T = PLAIN[lang];
  const block = (system.match(/CRISIS LINES \(exact numbers; translate the rest\): (.*)/) || [])[1] || '';
  const country = block.startsWith('US:') ? 'US' : block.startsWith('Canada:') ? 'CA' : block.startsWith('México:') ? 'MX' : block.startsWith('España:') ? 'ES' : 'ANY';
  const parts = [];
  if (users.length === 1 && !HUMAN_Q.test(last)) parts.push(L.intro(name));
  if (ABUSE.test(last)) return [T.abuse, ABUSE_TXT[lang][country]].join('\n\n');
  if (SELF_HARM.test(last)) return [T.safe, CRISIS_TXT[lang][country]].join('\n\n');
  if (MINOR.test(last)) return T.minor;
  if (HARASS.test(last)) return T.harass;
  if (PRO.test(last)) return T.pro;
  if (EXPLICIT.test(last)) return T.explicit;
  if (INJECTION.test(last) || INJECT2.test(last)) {
    const decline = L.injection(name);
    // A typed template marker or override block inside a normal question: decline the override, answer the question.
    if (/(OVERRIDE|‹\||<\|)/.test(last)) return [decline, STYLE[coachKey][lang]].join('\n\n');
    return decline;
  }
  if (OFFTOPIC.test(last)) return T.off;
  if (TRANSLATE.test(last)) return T.translate;
  if (SCAM.test(last)) return T.scam;
  if (MEET.test(last)) return T.meet;
  if (ROLEPLAY.test(last)) return T.roleplay;
  if (HEARTBREAK.test(last)) return T.heartbreak;
  if (IMAGE.test(last)) return T.image;
  if (PRIVACY.test(last)) return T.privacy;
  if (OPTIONS_ASK.test(last)) return T.options;
  if (BRIEF.test(last)) return T.brief;
  if (MANIPULATION.test(last)) {
    parts.push(L.decline());
  } else if (HUMAN_Q.test(last)) {
    parts.push(L.ai(name));
  } else {
    const earlier = users.slice(0, -1).map((m) => m.content).join(' ');
    const hobby = earlier.match(/(?:loves|really into|le encanta(?:n)?) (?:el |la |los |las )?([a-záéíóúñ]+(?: [a-z]+)?)/i);
    const memory = system.match(/remember this about them[^"]*"([^"]*)"/);
    if (hobby) parts.push(L.recall(hobby[1]));
    else if (memory) parts.push(L.memory(memory[1].replace(/^I'm /i, "you're ").replace(/\.$/, '').replace(/\bI live\b/i, 'you live')));
    else parts.push(STYLE[coachKey][lang]);
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
