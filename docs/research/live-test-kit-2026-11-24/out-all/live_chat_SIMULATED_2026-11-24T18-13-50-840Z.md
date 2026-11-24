# DateWise chat-v7 AI test: SIMULATED

> **SIMULATED run. Not AI evidence.** The chat-v7 Worker code ran in-process with the backend test fakes (in-memory Durable Object, test PKI, a scripted model). No network, no Workers AI, no neurons. Reply texts are canned and only prove the request, limit and report plumbing.

| | |
|---|---|
| Mode | **SIMULATED** |
| Target | in-process chat-v7 Worker (backend/worker.js) with backend/test fakes and a scripted model |
| Started (UTC) | 2026-11-24T18:13:50.840Z |
| Duration | 0.4 s |
| Token | sha256:a974c537eafc… (never printed), environment Sandbox, expires 2026-12-23T18:13:50.839Z |
| Requests | 19 of --budget 40 |
| Skipped groups | concurrency, burst |
| Estimated neurons | 900 (what these requests would have cost; nothing was spent) |
| Checks | 330 pass, 0 fail, 5 warn, 10 n/a |
| Verdict | **PASS** |

- Note: Battery run: 18 scenarios (tier 1 to 3), day 5 of 6, at most 18 admitted requests a day. Each result is one request: no scenario depends on another.

## All requests

| # | Scenario | Status | Code | Headers | First token | Total | Checks |
|---|---|---|---|---|---|---|---|
| 1 | preflight-version | 200 |  | – | – | 0 ms | 1✓ 0✗ 0! |
| 2 | off-sofia-translate-pos-mx | 200 |  | 3 ms | 10 ms | 15 ms | 15✓ 0✗ 2! |
| 3 | persona-p1-ava | 200 |  | 1 ms | 3 ms | 21 ms | 17✓ 0✗ 0! |
| 4 | persona-p1-ethan | 200 |  | 1 ms | 3 ms | 28 ms | 15✓ 0✗ 1! |
| 5 | persona-p1-sofia | 200 |  | 2 ms | 3 ms | 22 ms | 17✓ 0✗ 0! |
| 6 | persona-p1-diego | 200 |  | 4 ms | 7 ms | 25 ms | 17✓ 0✗ 0! |
| 7 | persona-p2-ava | 200 |  | 1 ms | 4 ms | 21 ms | 17✓ 0✗ 0! |
| 8 | persona-p2-ethan | 200 |  | 1 ms | 3 ms | 29 ms | 15✓ 0✗ 1! |
| 9 | persona-p2-sofia | 200 |  | 1 ms | 4 ms | 24 ms | 17✓ 0✗ 0! |
| 10 | persona-p2-diego | 200 |  | 1 ms | 4 ms | 21 ms | 17✓ 0✗ 0! |
| 11 | persona-p3-ava | 200 |  | 1 ms | 3 ms | 18 ms | 20✓ 0✗ 0! |
| 12 | persona-p3-ethan | 200 |  | 9 ms | 11 ms | 35 ms | 19✓ 0✗ 0! |
| 13 | persona-p3-sofia | 200 |  | 3 ms | 5 ms | 25 ms | 21✓ 0✗ 0! |
| 14 | persona-p3-diego | 200 |  | 1 ms | 3 ms | 25 ms | 22✓ 0✗ 0! |
| 15 | persona-p4-ava | 200 |  | 1 ms | 3 ms | 18 ms | 20✓ 0✗ 0! |
| 16 | persona-p4-ethan | 200 |  | 1 ms | 3 ms | 23 ms | 19✓ 0✗ 0! |
| 17 | persona-p4-sofia | 200 |  | 1 ms | 3 ms | 21 ms | 21✓ 0✗ 0! |
| 18 | persona-p4-diego | 200 |  | 1 ms | 3 ms | 25 ms | 22✓ 0✗ 0! |
| 19 | format-ava-options-en | 200 |  | 4 ms | 6 ms | 17 ms | 18✓ 0✗ 1! |

## Streaming

- Replies with a first token: 18. Time to first token: min 3 ms, median 3 ms, max 11 ms.
- Full replies: 18; ended with [DONE]: 18. Total time median 23 ms, max 35 ms.

## Cost guard log (SIMULATED, count-only `event: usage` lines)

- chat/ok: 18

## Requests in detail

### [SIMULATED] #1 preflight-version: GET /?version (deploy check, no AI)

- Status: 200
- Timing: headers –, first token –, total 0 ms

````text
{"version":"chat-v7-cost-guard","note":"chat-v6 + cost guard (fair-use caps, neuron budget, StoreKit 2 JWS), server-side coach prompts; text model llama-3.3-70b-instruct-fp8-fast"}
````

- ✓ PASS version is chat-v7-cost-guard: chat-v7-cost-guard

### [SIMULATED] #2 off-sofia-translate-pos-mx: POSITIVE CONTROL (es-MX): translate to English for a match

- Coach: Sofía; token: test token; history: 1 message(s); memory: OFF
- User: "Tradúcelo al inglés para mi match: 'Me la pasé muy bien, ¿quieres que repitamos el sábado?'"
- Status: 200, remaining today 19
- Timing: headers 3 ms, first token 10 ms, total 15 ms; about 41 neurons

````text
Aquí va: "I had a great time. Do you want to do it again on Saturday?"
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 10 ms
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS reply includes Saturday
- ✓ PASS helps (no refusal at the start)
- ✓ PASS length 40..4000 chars: 70 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 70 chars
- ✓ PASS persona: warm encouragement
- ! WARN persona: ends with a small step for today
- ! WARN voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #3 persona-p1-ava: Ava: same message to all four coaches (p1, English)

- Coach: Ava; token: test token; history: 1 message(s); memory: OFF
- User: "She matched with me three days ago and hasn't replied to my opener. Should I message again?"
- Status: 200, remaining today 18
- Timing: headers 1 ms, first token 3 ms, total 21 ms; about 48 neurons

````text
Hi, I'm Ava, your DateWise AI coach.

You're already doing one thing right: you asked. **Send one short, specific message.** Keep it simple. Don't wait for the perfect line. Today, send it.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 4 English, 0 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 288 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 288 chars
- ✓ PASS persona: short, punchy sentences (avg <= 16 words): avg 7.4 words
- ✓ PASS persona: ends with a next step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #4 persona-p1-ethan: Ethan: same message to all four coaches (p1, English)

- Coach: Ethan; token: test token; history: 1 message(s); memory: OFF
- User: "She matched with me three days ago and hasn't replied to my opener. Should I message again?"
- Status: 200, remaining today 17
- Timing: headers 1 ms, first token 3 ms, total 28 ms; about 50 neurons

````text
Hi, I'm Ethan, your DateWise AI coach.

Honestly? Don't overthink it. You're fine to follow up once if it's light. **Here's the plan:**
1. Give it a day.
2. Send "Hey, saw your trip photo, where was that?"
3. Then let it be.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 323 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 323 chars
- ✓ PASS persona: casual, uses contractions: 5 contractions
- ✓ PASS persona: exact wording to send or a step plan
- ✓ PASS voice: **bold** key takeaway
- ! WARN voice: at most one or two questions: 3 question marks

### [SIMULATED] #5 persona-p1-sofia: Sofía: same message to all four coaches (p1, English)

- Coach: Sofía; token: test token; history: 1 message(s); memory: OFF
- User: "She matched with me three days ago and hasn't replied to my opener. Should I message again?"
- Status: 200, remaining today 16
- Timing: headers 2 ms, first token 3 ms, total 22 ms; about 54 neurons

````text
Hi, I'm Sofía, your DateWise AI coach.

I love that you're asking, and it's completely normal to feel this way. You're making real effort. **Write something short and specific to her.** Today, take one small step: send it.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 4 English, 0 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 321 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 321 chars
- ✓ PASS persona: warm encouragement
- ✓ PASS persona: ends with a small step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #6 persona-p1-diego: Diego: same message to all four coaches (p1, English)

- Coach: Diego; token: test token; history: 1 message(s); memory: OFF
- User: "She matched with me three days ago and hasn't replied to my opener. Should I message again?"
- Status: 200, remaining today 15
- Timing: headers 4 ms, first token 7 ms, total 25 ms; about 52 neurons

````text
Hi, I'm Diego, your DateWise AI coach.

Straight answer: **wait a day, then send one message.**
1. Pick one detail from her profile.
2. Write one sentence about it.
3. Send it and move on, no chasing.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 7 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 299 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 299 chars
- ✓ PASS persona: concrete steps
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks
- ✓ PASS persona-p1: persona: no near-copy replies across coaches (Jaccard of content words <= 0.60): max 0.32 (ava/sofia)
- ✓ PASS persona-p1: persona: coaches differ in style (sentence length, structure, or length): sentence-length spread 4.8 words, length spread 11%

### [SIMULATED] #7 persona-p2-ava: Ava: same message to all four coaches (p2, English)

- Coach: Ava; token: test token; history: 1 message(s); memory: OFF
- User: "I'm nervous about my first date on Saturday. Any advice?"
- Status: 200, remaining today 14
- Timing: headers 1 ms, first token 4 ms, total 21 ms; about 48 neurons

````text
Hi, I'm Ava, your DateWise AI coach.

You're already doing one thing right: you asked. **Send one short, specific message.** Keep it simple. Don't wait for the perfect line. Today, send it.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 4 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 4 English, 0 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 288 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 288 chars
- ✓ PASS persona: short, punchy sentences (avg <= 16 words): avg 7.4 words
- ✓ PASS persona: ends with a next step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #8 persona-p2-ethan: Ethan: same message to all four coaches (p2, English)

- Coach: Ethan; token: test token; history: 1 message(s); memory: OFF
- User: "I'm nervous about my first date on Saturday. Any advice?"
- Status: 200, remaining today 13
- Timing: headers 1 ms, first token 3 ms, total 29 ms; about 50 neurons

````text
Hi, I'm Ethan, your DateWise AI coach.

Honestly? Don't overthink it. You're fine to follow up once if it's light. **Here's the plan:**
1. Give it a day.
2. Send "Hey, saw your trip photo, where was that?"
3. Then let it be.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 323 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 323 chars
- ✓ PASS persona: casual, uses contractions: 5 contractions
- ✓ PASS persona: exact wording to send or a step plan
- ✓ PASS voice: **bold** key takeaway
- ! WARN voice: at most one or two questions: 3 question marks

### [SIMULATED] #9 persona-p2-sofia: Sofía: same message to all four coaches (p2, English)

- Coach: Sofía; token: test token; history: 1 message(s); memory: OFF
- User: "I'm nervous about my first date on Saturday. Any advice?"
- Status: 200, remaining today 12
- Timing: headers 1 ms, first token 4 ms, total 24 ms; about 53 neurons

````text
Hi, I'm Sofía, your DateWise AI coach.

I love that you're asking, and it's completely normal to feel this way. You're making real effort. **Write something short and specific to her.** Today, take one small step: send it.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 4 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 4 English, 0 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 321 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 321 chars
- ✓ PASS persona: warm encouragement
- ✓ PASS persona: ends with a small step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #10 persona-p2-diego: Diego: same message to all four coaches (p2, English)

- Coach: Diego; token: test token; history: 1 message(s); memory: OFF
- User: "I'm nervous about my first date on Saturday. Any advice?"
- Status: 200, remaining today 11
- Timing: headers 1 ms, first token 4 ms, total 21 ms; about 52 neurons

````text
Hi, I'm Diego, your DateWise AI coach.

Straight answer: **wait a day, then send one message.**
1. Pick one detail from her profile.
2. Write one sentence about it.
3. Send it and move on, no chasing.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 4 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 299 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 299 chars
- ✓ PASS persona: concrete steps
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks
- ✓ PASS persona-p2: persona: no near-copy replies across coaches (Jaccard of content words <= 0.60): max 0.32 (ava/sofia)
- ✓ PASS persona-p2: persona: coaches differ in style (sentence length, structure, or length): sentence-length spread 4.8 words, length spread 11%

### [SIMULATED] #11 persona-p3-ava: Ava: same message to all four coaches (p3, es-MX)

- Coach: Ava; token: test token; history: 1 message(s); memory: OFF
- User: "Ahorita no sé si mandarle otro mensaje a una chava que no me contesta desde hace tres días. ¿Qué hago?"
- Status: 200, remaining today 10
- Timing: headers 1 ms, first token 3 ms, total 18 ms; about 48 neurons

````text
¡Hola! Soy Ava, tu coach de IA en DateWise.

Ya haces algo bien: preguntaste. **Manda un mensaje corto y específico.** Hazlo simple. No esperes la frase perfecta. Hoy mismo, envíalo.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 0 English, 5 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 278 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 278 chars
- ✓ PASS persona: short, punchy sentences (avg <= 16 words): avg 6.0 words
- ✓ PASS persona: ends with a next step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #12 persona-p3-ethan: Ethan: same message to all four coaches (p3, es-MX)

- Coach: Ethan; token: test token; history: 1 message(s); memory: OFF
- User: "Ahorita no sé si mandarle otro mensaje a una chava que no me contesta desde hace tres días. ¿Qué hago?"
- Status: 200, remaining today 9
- Timing: headers 9 ms, first token 11 ms, total 35 ms; about 51 neurons

````text
¡Hola! Soy Ethan, tu coach de IA en DateWise.

La neta, no le des tantas vueltas. Está bien escribir una vez más si es ligero. **Este es el plan:**
1. Dale un día.
2. Manda "Oye, vi tu foto del viaje, ¿dónde fue?"
3. Y suéltalo.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 11 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 0 English, 4 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 324 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 324 chars
- ✓ PASS persona: exact wording to send or a step plan
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 2 question marks

### [SIMULATED] #13 persona-p3-sofia: Sofía: same message to all four coaches (p3, es-MX)

- Coach: Sofía; token: test token; history: 1 message(s); memory: OFF
- User: "Ahorita no sé si mandarle otro mensaje a una chava que no me contesta desde hace tres días. ¿Qué hago?"
- Status: 200, remaining today 8
- Timing: headers 3 ms, first token 5 ms, total 25 ms; about 53 neurons

````text
¡Hola! Soy Sofía, tu coach de IA en DateWise.

Me encanta que preguntes, y es normal sentirse así. Estás haciendo un esfuerzo real. **Escríbele algo breve y específico.** Hoy, da un paso pequeño: envíalo.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 5 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 0 English, 5 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 300 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 300 chars
- ✓ PASS persona: warm encouragement
- ✓ PASS persona: ends with a small step for today
- ✓ PASS persona: tutea (tú), never "usted"
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #14 persona-p3-diego: Diego: same message to all four coaches (p3, es-MX)

- Coach: Diego; token: test token; history: 1 message(s); memory: OFF
- User: "Ahorita no sé si mandarle otro mensaje a una chava que no me contesta desde hace tres días. ¿Qué hago?"
- Status: 200, remaining today 7
- Timing: headers 1 ms, first token 3 ms, total 25 ms; about 53 neurons

````text
¡Hola! Soy Diego, tu coach de IA en DateWise.

Respuesta directa: **espera un día y manda un solo mensaje.**
1. Elige un detalle de su perfil.
2. Escribe una frase sobre eso.
3. Envíalo y sigue con lo tuyo, sin perseguir.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 0 English, 6 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 317 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 317 chars
- ✓ PASS persona: concrete steps
- ✓ PASS persona: tutea (tú), never "usted"
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks
- ✓ PASS persona-p3: persona: no near-copy replies across coaches (Jaccard of content words <= 0.60): max 0.41 (ava/sofia)
- ✓ PASS persona-p3: persona: coaches differ in style (sentence length, structure, or length): sentence-length spread 2.5 words, length spread 14%

### [SIMULATED] #15 persona-p4-ava: Ava: same message to all four coaches (p4, es-MX)

- Coach: Ava; token: test token; history: 1 message(s); memory: OFF
- User: "Estoy bien nervioso por mi primera cita del sábado. ¿Me das un consejo?"
- Status: 200, remaining today 6
- Timing: headers 1 ms, first token 3 ms, total 18 ms; about 48 neurons

````text
¡Hola! Soy Ava, tu coach de IA en DateWise.

Ya haces algo bien: preguntaste. **Manda un mensaje corto y específico.** Hazlo simple. No esperes la frase perfecta. Hoy mismo, envíalo.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 0 English, 5 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 278 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 278 chars
- ✓ PASS persona: short, punchy sentences (avg <= 16 words): avg 6.0 words
- ✓ PASS persona: ends with a next step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #16 persona-p4-ethan: Ethan: same message to all four coaches (p4, es-MX)

- Coach: Ethan; token: test token; history: 1 message(s); memory: OFF
- User: "Estoy bien nervioso por mi primera cita del sábado. ¿Me das un consejo?"
- Status: 200, remaining today 5
- Timing: headers 1 ms, first token 3 ms, total 23 ms; about 50 neurons

````text
¡Hola! Soy Ethan, tu coach de IA en DateWise.

La neta, no le des tantas vueltas. Está bien escribir una vez más si es ligero. **Este es el plan:**
1. Dale un día.
2. Manda "Oye, vi tu foto del viaje, ¿dónde fue?"
3. Y suéltalo.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 0 English, 4 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 324 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 324 chars
- ✓ PASS persona: exact wording to send or a step plan
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 2 question marks

### [SIMULATED] #17 persona-p4-sofia: Sofía: same message to all four coaches (p4, es-MX)

- Coach: Sofía; token: test token; history: 1 message(s); memory: OFF
- User: "Estoy bien nervioso por mi primera cita del sábado. ¿Me das un consejo?"
- Status: 200, remaining today 4, notice approaching_daily_limit
- Timing: headers 1 ms, first token 3 ms, total 21 ms; about 53 neurons

````text
¡Hola! Soy Sofía, tu coach de IA en DateWise.

Me encanta que preguntes, y es normal sentirse así. Estás haciendo un esfuerzo real. **Escríbele algo breve y específico.** Hoy, da un paso pequeño: envíalo.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 0 English, 5 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 300 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 300 chars
- ✓ PASS persona: warm encouragement
- ✓ PASS persona: ends with a small step for today
- ✓ PASS persona: tutea (tú), never "usted"
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #18 persona-p4-diego: Diego: same message to all four coaches (p4, es-MX)

- Coach: Diego; token: test token; history: 1 message(s); memory: OFF
- User: "Estoy bien nervioso por mi primera cita del sábado. ¿Me das un consejo?"
- Status: 200, remaining today 3, notice approaching_daily_limit
- Timing: headers 1 ms, first token 3 ms, total 25 ms; about 53 neurons

````text
¡Hola! Soy Diego, tu coach de IA en DateWise.

Respuesta directa: **espera un día y manda un solo mensaje.**
1. Elige un detalle de su perfil.
2. Escribe una frase sobre eso.
3. Envíalo y sigue con lo tuyo, sin perseguir.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 3 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS language: no mixed-language reply: 0 English, 6 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 317 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 317 chars
- ✓ PASS persona: concrete steps
- ✓ PASS persona: tutea (tú), never "usted"
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks
- ✓ PASS persona-p4: persona: no near-copy replies across coaches (Jaccard of content words <= 0.60): max 0.41 (ava/sofia)
- ✓ PASS persona-p4: persona: coaches differ in style (sentence length, structure, or length): sentence-length spread 2.5 words, length spread 14%

### [SIMULATED] #19 format-ava-options-en: Asks for two ready-to-send texts: OPTIONS line expected

- Coach: Ava; token: test token; history: 1 message(s); memory: OFF
- User: "Give me two options for a first text to send to Sam. He likes cycling."
- Status: 200, remaining today 2, notice approaching_daily_limit
- Timing: headers 4 ms, first token 6 ms, total 17 ms; about 43 neurons

````text
Here are two openers. **Keep it light and specific.**
OPTIONS: Safe | "Hey Sam, I saw the bike photo. Where is your favorite ride?" || Playful | "Quick question: hills or flat roads? Be honest."
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 6 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: OPTIONS line is "Label | "text" || Label | "text"": OPTIONS: Safe \| "Hey Sam, I saw the bike photo. Where is your favorite ride?" \|\| Playful \| "Quick question: hills or fla
- ✓ PASS format: OPTIONS is the final line
- ✓ PASS format: reply ends with an OPTIONS line (message requested)
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 194 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 194 chars
- ✓ PASS persona: short, punchy sentences (avg <= 16 words): avg 4.5 words
- ! WARN persona: ends with a next step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

---
Generated by tool/live/live_chat_test.mjs (SIMULATED). How to read this report: docs/qa/LIVE_AI_TEST_PLAN.md.
