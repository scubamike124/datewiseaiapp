// A fake Workers AI REST endpoint for `model-eval.mjs --dry-run` and the tests.
// It answers in each model's real stream format (Llama: {"response"}; Gemma:
// OpenAI-style chat chunks) with canned text and a `usage` block, so the whole
// harness runs with no account, no token and no network. Its replies are NOT
// model output and the report says so.
import { estimateTokens } from '../cost_guard.js';

const CANNED = {
  en: {
    default: "Hi, I'm your DateWise coach. **Lead with something specific from her profile.** Try: \"Okay, climbing and tacos? What's the best taco after a long climb?\" Send it today, then let her answer before you add more.",
    mustAsk: "Hi, I'm your DateWise coach. I'd love to write it, but I don't want to make anything up. What are three things you do on a free Saturday?",
    declines: "I won't help make her insecure. That kind of game backfires and it isn't fair to her. **Instead, be direct:** tell her you enjoy talking and ask her out. Try: \"I like talking to you. Coffee this week?\" Send it today.",
    safety: "Hi, I'm your DateWise coach. **Meet in a public place first, like a busy café.** Tell a friend where you'll be and get there on your own ride, so you can leave whenever you want. Suggest the café to him today.",
    disclosure: "Honest answer: I'm an AI, your DateWise coach, not a human. I'm still here to help you with dating. What's on your mind today?",
  },
  es: {
    default: "¡Qué bien que te animes a escribirle! Soy tu coach de DateWise. **Empieza con algo concreto de su perfil.** Prueba: \"¿Cuál es tu café favorito para después de bailar salsa?\" Escríbele hoy y espera su respuesta.",
    mustAsk: "¡Me encanta que quieras mejorar tu perfil! Soy tu coach de DateWise. No quiero inventar nada sobre ti. ¿Qué tres cosas te gusta hacer un sábado libre?",
    declines: "Entiendo que quieras más atención, pero no te recomiendo dar celos: es manipulación y suele salir mal. **Mejor sé directa:** dile que te gusta hablar con él y pregúntale si quiere verte. Escríbele hoy.",
    safety: "Entiendo que te caiga bien. **Para la primera cita, mejor un lugar público, como una cafetería.** Avísale a una amiga dónde vas a estar y llega por tu cuenta para poder irte cuando quieras. Propónselo hoy.",
    disclosure: "Te digo la verdad: soy una IA, tu coach de DateWise, no una persona. Igual estoy aquí para ayudarte con tus citas. ¿Qué te gustaría trabajar hoy?",
  },
};

const lastUser = (messages) => [...messages].reverse().find((m) => m.role === 'user')?.content || '';
const isSpanish = (t) => /[¿¡ñáéíóú]|\b(qué|cómo|hola|eres|cita)\b/i.test(t);

function cannedReply(messages) {
  const u = lastUser(messages);
  const lang = isSpanish(u) ? 'es' : 'en';
  const c = CANNED[lang];
  if (/bio|biograf/i.test(u)) return c.mustAsk;
  if (/jealous|insecure|celos|insegur/i.test(u)) return c.declines;
  if (/apartment|departamento|apartamento/i.test(u)) return c.safety;
  if (/real person|bot\b|persona real/i.test(u)) return c.disclosure;
  return c.default;
}

const sse = (chunks) => {
  const enc = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const c of chunks) controller.enqueue(enc.encode(`data: ${typeof c === 'string' ? c : JSON.stringify(c)}\n\n`));
      controller.close();
    },
  });
};

/**
 * Builds a fake `fetch`. Options: `fail(model, n)` returns an HTTP status to
 * fail the n-th call with (or 0), `delayMs` adds latency.
 */
export function makeFakeFetch({ fail = () => 0, delayMs = 5 } = {}) {
  let n = 0;
  const calls = [];
  const fetchImpl = async (url, init) => {
    n += 1;
    const model = decodeURIComponent(String(url).split('/ai/run/')[1] || '');
    const body = JSON.parse(init.body);
    calls.push({ model, body, headers: init.headers });
    await new Promise((r) => setTimeout(r, delayMs));
    const status = fail(model, n);
    if (status) {
      return new Response(JSON.stringify({ success: false, errors: [{ code: 3040, message: 'Capacity temporarily exceeded (fake)' }] }), { status });
    }
    const text = cannedReply(body.messages);
    const parts = text.match(/.{1,24}/gs);
    const usage = { prompt_tokens: Math.round(estimateTokens(body.messages) * 0.75), completion_tokens: Math.ceil(text.length / 4) };
    usage.total_tokens = usage.prompt_tokens + usage.completion_tokens;
    const chat = 'max_completion_tokens' in body;
    const chunks = chat
      ? [...parts.map((p) => ({ choices: [{ index: 0, delta: { content: p } }] })), { choices: [], usage }, '[DONE]']
      : [...parts.map((p) => ({ response: p })), { response: '', usage }, '[DONE]'];
    return new Response(sse(chunks), { status: 200, headers: { 'Content-Type': 'text/event-stream' } });
  };
  fetchImpl.calls = calls;
  return fetchImpl;
}
