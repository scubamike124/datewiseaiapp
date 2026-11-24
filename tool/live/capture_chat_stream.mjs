// Writes the exact bytes the local chat-v7 Worker (backend/worker.js, scripted model) streams for one reply:
//   node tool/live/capture_chat_stream.mjs test/fixtures/chat_v7_stream_es.sse
import { createLocalTarget } from './local_harness.mjs';
import { writeFileSync } from 'node:fs';
const t = await createLocalTarget({ vars: {} });
const body = { tier: 'premium', coachId: 'sofia', messages: [{ role: 'user', content: 'How do I start a chat?' }] };
const res = await t.fetch('https://simulated.invalid/', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-DateWise-Entitlement': t.jws }, body: JSON.stringify(body) });
const buf = Buffer.from(await res.arrayBuffer());
console.error(res.status, res.headers.get('content-type'), buf.length);
writeFileSync(process.argv[2], buf);
await t.close();
