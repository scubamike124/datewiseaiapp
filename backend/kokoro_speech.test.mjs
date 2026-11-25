import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handleSpeech, validateSpeechRequest, KOKORO_VOICES } from './kokoro_speech.mjs';

const good = { text: 'Hi there.', voice: 'af_bella', lang: 'en-us', speed: 0.85 };
const post = (obj, extra = {}) => ({
  method: 'POST',
  contentType: 'application/json',
  rawBody: typeof obj === 'string' ? obj : JSON.stringify(obj),
  ...extra,
});

test('every app voice is a known Kokoro voice with a matching language', () => {
  assert.deepEqual(KOKORO_VOICES, { af_bella: 'en-us', am_michael: 'en-us', ef_dora: 'es', em_alex: 'es' });
});

test('a valid request is accepted', () => {
  assert.equal(validateSpeechRequest(good).ok, true);
});

test('invalid bodies are refused with a reason', () => {
  const bad = [
    null,
    [],
    { ...good, text: '   ' },
    { ...good, text: 'x'.repeat(1001) },
    { ...good, voice: 'af_unknown' },
    { ...good, voice: 'ef_dora' }, // Spanish voice with an English lang
    { ...good, lang: 'es' },
    { ...good, speed: 0 },
    { ...good, speed: 2 },
    { ...good, speed: 'fast' },
  ];
  for (const b of bad) assert.equal(validateSpeechRequest(b).ok, false, JSON.stringify(b));
});

test('the coach rate range maps to a speed inside the accepted range', () => {
  for (const speed of [0.836, 0.864]) {
    assert.equal(validateSpeechRequest({ ...good, speed }).ok, true);
  }
});

test('only POST is accepted', async () => {
  const r = await handleSpeech({ ...post(good), method: 'GET' }, { render: async () => ({}) });
  assert.equal(r.status, 405);
});

test('only JSON bodies are accepted', async () => {
  const r = await handleSpeech(post(good, { contentType: 'text/plain' }), { render: async () => ({}) });
  assert.equal(r.status, 415);
});

test('malformed JSON and invalid fields are 400', async () => {
  assert.equal((await handleSpeech(post('{nope'), {})).status, 400);
  const r = await handleSpeech(post({ ...good, voice: 'nope' }), { render: async () => ({}) });
  assert.equal(r.status, 400);
  assert.equal(r.json.error, 'invalid_request');
});

test('without a renderer the stub answers 503 and renders nothing', async () => {
  const r = await handleSpeech(post(good), {});
  assert.equal(r.status, 503);
  assert.equal(r.json.error, 'not_configured');
});

test('a renderer reply is passed through in the contract shape', async () => {
  let seen = null;
  const timeline = { fps: 10, sentences: [] };
  const r = await handleSpeech(post(good), {
    render: async (v) => {
      seen = v;
      return { timeline, audio_url: '/clips/a.wav' };
    },
  });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { timeline, audio_url: '/clips/a.wav' });
  assert.deepEqual(seen, good);
});

test('a renderer that returns no audio url is a 500, a renderer that throws is a 502', async () => {
  const a = await handleSpeech(post(good), { render: async () => ({ timeline: {} }) });
  assert.equal(a.status, 500);
  const b = await handleSpeech(post(good), {
    render: async () => {
      throw new Error('model file missing at /secret/path');
    },
  });
  assert.equal(b.status, 502);
  assert.equal(JSON.stringify(b.json).includes('secret'), false, 'render errors are not echoed');
});
