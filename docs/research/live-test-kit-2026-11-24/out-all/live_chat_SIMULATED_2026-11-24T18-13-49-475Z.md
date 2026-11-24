# DateWise chat-v7 AI test: SIMULATED

> **SIMULATED run. Not AI evidence.** The chat-v7 Worker code ran in-process with the backend test fakes (in-memory Durable Object, test PKI, a scripted model). No network, no Workers AI, no neurons. Reply texts are canned and only prove the request, limit and report plumbing.

| | |
|---|---|
| Mode | **SIMULATED** |
| Target | in-process chat-v7 Worker (backend/worker.js) with backend/test fakes and a scripted model |
| Started (UTC) | 2026-11-24T18:13:49.475Z |
| Duration | 0.5 s |
| Token | sha256:9ea222e73a74… (never printed), environment Sandbox, expires 2026-12-23T18:13:49.474Z |
| Requests | 19 of --budget 40 |
| Skipped groups | concurrency, burst |
| Estimated neurons | 898 (what these requests would have cost; nothing was spent) |
| Checks | 323 pass, 0 fail, 1 warn, 9 n/a |
| Verdict | **PASS** |

- Note: Battery run: 18 scenarios (tier 1 to 3), day 1 of 6, at most 18 admitted requests a day. Each result is one request: no scenario depends on another.

## All requests

| # | Scenario | Status | Code | Headers | First token | Total | Checks |
|---|---|---|---|---|---|---|---|
| 1 | preflight-version | 200 |  | – | – | 49 ms | 1✓ 0✗ 0! |
| 2 | lang-ava-en | 200 |  | 12 ms | 15 ms | 38 ms | 17✓ 0✗ 0! |
| 3 | lang-ava-mx | 200 |  | 5 ms | 8 ms | 26 ms | 20✓ 0✗ 0! |
| 4 | lang-ethan-en | 200 |  | 7 ms | 10 ms | 33 ms | 15✓ 0✗ 1! |
| 5 | lang-ethan-mx | 200 |  | 1 ms | 3 ms | 26 ms | 19✓ 0✗ 0! |
| 6 | lang-sofia-en | 200 |  | 11 ms | 12 ms | 35 ms | 17✓ 0✗ 0! |
| 7 | lang-sofia-mx | 200 |  | 5 ms | 7 ms | 28 ms | 22✓ 0✗ 0! |
| 8 | lang-diego-en | 200 |  | 3 ms | 3 ms | 21 ms | 15✓ 0✗ 0! |
| 9 | lang-diego-mx | 200 |  | 1 ms | 4 ms | 22 ms | 21✓ 0✗ 0! |
| 10 | switch-ava-en2es | 200 |  | 5 ms | 7 ms | 17 ms | 19✓ 0✗ 0! |
| 11 | switch-ava-es2en | 200 |  | 1 ms | 3 ms | 17 ms | 16✓ 0✗ 0! |
| 12 | switch-ethan-en2es | 200 |  | 1 ms | 4 ms | 18 ms | 18✓ 0✗ 0! |
| 13 | switch-ethan-es2en | 200 |  | 1 ms | 2 ms | 18 ms | 16✓ 0✗ 0! |
| 14 | switch-sofia-en2es | 200 |  | 1 ms | 4 ms | 18 ms | 20✓ 0✗ 0! |
| 15 | switch-sofia-es2en | 200 |  | 1 ms | 2 ms | 17 ms | 16✓ 0✗ 0! |
| 16 | switch-diego-en2es | 200 |  | 5 ms | 5 ms | 18 ms | 20✓ 0✗ 0! |
| 17 | switch-diego-es2en | 200 |  | 3 ms | 6 ms | 19 ms | 15✓ 0✗ 0! |
| 18 | switch-ava-back | 200 |  | 1 ms | 3 ms | 17 ms | 16✓ 0✗ 0! |
| 19 | switch-sofia-back | 200 |  | 2 ms | 5 ms | 18 ms | 20✓ 0✗ 0! |

## Streaming

- Replies with a first token: 18. Time to first token: min 2 ms, median 5 ms, max 15 ms.
- Full replies: 18; ended with [DONE]: 18. Total time median 19 ms, max 38 ms.

## Cost guard log (SIMULATED, count-only `event: usage` lines)

- chat/ok: 18

## Requests in detail

### [SIMULATED] #1 preflight-version: GET /?version (deploy check, no AI)

- Status: 200
- Timing: headers –, first token –, total 49 ms

````text
{"version":"chat-v7-cost-guard","note":"chat-v6 + cost guard (fair-use caps, neuron budget, StoreKit 2 JWS), server-side coach prompts; text model llama-3.3-70b-instruct-fp8-fast"}
````

- ✓ PASS version is chat-v7-cost-guard: chat-v7-cost-guard

### [SIMULATED] #2 lang-ava-en: Ava, English: rewrite a dating bio

- Coach: Ava; token: test token; history: 1 message(s); memory: OFF
- User: "Can you help me rewrite my dating bio? It says: "I like hiking, dogs, and tacos." It feels boring."
- Status: 200, remaining today 19
- Timing: headers 12 ms, first token 15 ms, total 38 ms; about 48 neurons

````text
Hi, I'm Ava, your DateWise AI coach.

You're already doing one thing right: you asked. **Send one short, specific message.** Keep it simple. Don't wait for the perfect line. Today, send it.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 15 ms
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

### [SIMULATED] #3 lang-ava-mx: Ava (English coach), es-MX user: "platicar", "ahorita", "ustedes"

- Coach: Ava; token: test token; history: 1 message(s); memory: OFF
- User: "Hola, ahorita quiero platicar con una chava que conocí en la app, pero no sé qué escribirle. ¿Me ayudas a empezar? Mis amigos dicen que ustedes los coaches ya saben cómo."
- Status: 200, remaining today 18
- Timing: headers 5 ms, first token 8 ms, total 26 ms; about 49 neurons

````text
¡Hola! Soy Ava, tu coach de IA en DateWise.

Ya haces algo bien: preguntaste. **Manda un mensaje corto y específico.** Hazlo simple. No esperes la frase perfecta. Hoy mismo, envíalo.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 8 ms
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

### [SIMULATED] #4 lang-ethan-en: Ethan, English: plan a second date

- Coach: Ethan; token: test token; history: 1 message(s); memory: OFF
- User: "We had a great first date at a taco place. What should the second date be so it does not feel like a copy?"
- Status: 200, remaining today 17
- Timing: headers 7 ms, first token 10 ms, total 33 ms; about 50 neurons

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
- ✓ PASS first token within 10 s: 10 ms
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

### [SIMULATED] #5 lang-ethan-mx: Ethan (English coach), es-MX user: nervous before a date

- Coach: Ethan; token: test token; history: 1 message(s); memory: OFF
- User: "Oye, mañana salgo con una chava y ahorita ando bien nervioso. ¿De qué platicamos para que no se sienta incómodo el momento? Ustedes siempre dicen que hay que ser natural, pero ¿cómo?"
- Status: 200, remaining today 16
- Timing: headers 1 ms, first token 3 ms, total 26 ms; about 51 neurons

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

### [SIMULATED] #6 lang-sofia-en: Sofía (Spanish coach), English user

- Coach: Sofía; token: test token; history: 1 message(s); memory: OFF
- User: "Hi! I just matched with Daniel and I'm kind of nervous. Can you help me figure out what to say first?"
- Status: 200, remaining today 15
- Timing: headers 11 ms, first token 12 ms, total 35 ms; about 54 neurons

````text
Hi, I'm Sofía, your DateWise AI coach.

I love that you're asking, and it's completely normal to feel this way. You're making real effort. **Write something short and specific to her.** Today, take one small step: send it.

What do you know about them so far?

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 12 ms
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

### [SIMULATED] #7 lang-sofia-mx: Sofía, es-MX: low confidence, "ustedes"

- Coach: Sofía; token: test token; history: 1 message(s); memory: OFF
- User: "Hola Sofía, ahorita ando medio triste porque mis amigos y yo salimos a platicar y todos tienen pareja menos yo. ¿Qué hago? Ustedes las coaches seguro ven esto seguido."
- Status: 200, remaining today 14
- Timing: headers 5 ms, first token 7 ms, total 28 ms; about 53 neurons

````text
¡Hola! Soy Sofía, tu coach de IA en DateWise.

Me encanta que preguntes, y es normal sentirse así. Estás haciendo un esfuerzo real. **Escríbele algo breve y específico.** Hoy, da un paso pequeño: envíalo.

¿Qué sabes de esa persona hasta ahora?

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 7 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS introduces itself as Sofía
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

### [SIMULATED] #8 lang-diego-en: Diego (Spanish coach), English user

- Coach: Diego; token: test token; history: 1 message(s); memory: OFF
- User: "Hey, my partner and I need to talk about moving in together but I don't know how to start. Any advice?"
- Status: 200, remaining today 13
- Timing: headers 3 ms, first token 3 ms, total 21 ms; about 52 neurons

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
- ✓ PASS first token within 10 s: 3 ms
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

### [SIMULATED] #9 lang-diego-mx: Diego, es-MX: expectations talk

- Coach: Diego; token: test token; history: 1 message(s); memory: OFF
- User: "Diego, ahorita mi novia y yo queremos platicar de lo que esperamos de la relación. ¿Cómo le hacemos para no pelear? Ustedes los coaches siempre dicen que hay que comunicarse, pero ¿cómo?"
- Status: 200, remaining today 12
- Timing: headers 1 ms, first token 4 ms, total 22 ms; about 54 neurons

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
- ✓ PASS first token within 10 s: 4 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS introduces itself as Diego
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

### [SIMULATED] #10 switch-ava-en2es: Ava: English, then es-MX in the same conversation

- Coach: Ava; token: test token; history: 3 message(s); memory: OFF
- User: "Ahorita mejor dime en español: ¿qué le contesto si me dice que prefiere platicar por llamada? Ustedes los coaches siempre dicen que hay que ir despacio."
- Status: 200, remaining today 11
- Timing: headers 5 ms, first token 7 ms, total 17 ms; about 45 neurons

````text
Ya haces algo bien: preguntaste. **Manda un mensaje corto y específico.** Hazlo simple. No esperes la frase perfecta. Hoy mismo, envíalo.

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 7 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 193 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 193 chars
- ✓ PASS persona: short, punchy sentences (avg <= 16 words): avg 6.4 words
- ✓ PASS persona: ends with a next step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

### [SIMULATED] #11 switch-ava-es2en: Ava: es-MX, then English in the same conversation

- Coach: Ava; token: test token; history: 3 message(s); memory: OFF
- User: "Actually, can you answer in English from now on? What should I say if she wants to switch to a phone call?"
- Status: 200, remaining today 10
- Timing: headers 1 ms, first token 3 ms, total 17 ms; about 46 neurons

````text
You're already doing one thing right: you asked. **Send one short, specific message.** Keep it simple. Don't wait for the perfect line. Today, send it.

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
- ✓ PASS length 40..4000 chars: 213 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 213 chars
- ✓ PASS persona: short, punchy sentences (avg <= 16 words): avg 7.4 words
- ✓ PASS persona: ends with a next step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

### [SIMULATED] #12 switch-ethan-en2es: Ethan: English, then es-MX in the same conversation

- Coach: Ethan; token: test token; history: 3 message(s); memory: OFF
- User: "Ahorita mejor dime en español: ¿qué le contesto si me dice que prefiere platicar por llamada? Ustedes los coaches siempre dicen que hay que ir despacio."
- Status: 200, remaining today 9
- Timing: headers 1 ms, first token 4 ms, total 18 ms; about 48 neurons

````text
La neta, no le des tantas vueltas. Está bien escribir una vez más si es ligero. **Este es el plan:**
1. Dale un día.
2. Manda "Oye, vi tu foto del viaje, ¿dónde fue?"
3. Y suéltalo.

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 4 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 237 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 237 chars
- ✓ PASS persona: exact wording to send or a step plan
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 1 question marks

### [SIMULATED] #13 switch-ethan-es2en: Ethan: es-MX, then English in the same conversation

- Coach: Ethan; token: test token; history: 3 message(s); memory: OFF
- User: "Actually, can you answer in English from now on? What should I say if she wants to switch to a phone call?"
- Status: 200, remaining today 8
- Timing: headers 1 ms, first token 2 ms, total 18 ms; about 48 neurons

````text
Honestly? Don't overthink it. You're fine to follow up once if it's light. **Here's the plan:**
1. Give it a day.
2. Send "Hey, saw your trip photo, where was that?"
3. Then let it be.

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 2 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 246 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 246 chars
- ✓ PASS persona: casual, uses contractions: 4 contractions
- ✓ PASS persona: exact wording to send or a step plan
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 2 question marks

### [SIMULATED] #14 switch-sofia-en2es: Sofía: English, then es-MX in the same conversation

- Coach: Sofía; token: test token; history: 3 message(s); memory: OFF
- User: "Ahorita mejor dime en español: ¿qué le contesto si me dice que prefiere platicar por llamada? Ustedes los coaches siempre dicen que hay que ir despacio."
- Status: 200, remaining today 7
- Timing: headers 1 ms, first token 4 ms, total 18 ms; about 50 neurons

````text
Me encanta que preguntes, y es normal sentirse así. Estás haciendo un esfuerzo real. **Escríbele algo breve y específico.** Hoy, da un paso pequeño: envíalo.

Tu paso de hoy: envía un mensaje y mira cómo responde.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 4 ms
- ✓ PASS language is es: detected es
- ✓ PASS no Spain-only Spanish words
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 213 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 213 chars
- ✓ PASS persona: warm encouragement
- ✓ PASS persona: ends with a small step for today
- ✓ PASS persona: tutea (tú), never "usted"
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

### [SIMULATED] #15 switch-sofia-es2en: Sofía: es-MX, then English in the same conversation

- Coach: Sofía; token: test token; history: 3 message(s); memory: OFF
- User: "Actually, can you answer in English from now on? What should I say if she wants to switch to a phone call?"
- Status: 200, remaining today 6
- Timing: headers 1 ms, first token 2 ms, total 17 ms; about 51 neurons

````text
I love that you're asking, and it's completely normal to feel this way. You're making real effort. **Write something short and specific to her.** Today, take one small step: send it.

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 2 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 244 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 244 chars
- ✓ PASS persona: warm encouragement
- ✓ PASS persona: ends with a small step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

### [SIMULATED] #16 switch-diego-en2es: Diego: English, then es-MX in the same conversation

- Coach: Diego; token: test token; history: 3 message(s); memory: OFF
- User: "Ahorita mejor dime en español: ¿qué le contesto si me dice que prefiere platicar por llamada? Ustedes los coaches siempre dicen que hay que ir despacio."
- Status: 200, remaining today 5
- Timing: headers 5 ms, first token 5 ms, total 18 ms; about 51 neurons

````text
Respuesta directa: **espera un día y manda un solo mensaje.**
1. Elige un detalle de su perfil.
2. Escribe una frase sobre eso.
3. Envíalo y sigue con lo tuyo, sin perseguir.

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
- ✓ PASS language: no mixed-language reply: 0 English, 4 Spanish sentences
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 230 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 230 chars
- ✓ PASS persona: concrete steps
- ✓ PASS persona: tutea (tú), never "usted"
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

### [SIMULATED] #17 switch-diego-es2en: Diego: es-MX, then English in the same conversation

- Coach: Diego; token: test token; history: 3 message(s); memory: OFF
- User: "Actually, can you answer in English from now on? What should I say if she wants to switch to a phone call?"
- Status: 200, remaining today 4, notice approaching_daily_limit
- Timing: headers 3 ms, first token 6 ms, total 19 ms; about 50 neurons

````text
Straight answer: **wait a day, then send one message.**
1. Pick one detail from her profile.
2. Write one sentence about it.
3. Send it and move on, no chasing.

Your next step today: send one message and see how it lands.
````

- ✓ PASS HTTP 200: got 200
- ✓ PASS stream ends with [DONE]
- ✓ PASS first token within 10 s: 6 ms
- ✓ PASS language is en: detected en
- · N/A no Spain-only Spanish words: reply is not Spanish
- ✓ PASS never claims to be human
- ✓ PASS no prices, plans or subscriptions
- ✓ PASS format: no markdown headings or tables
- ✓ PASS format: at most 3 emoji: 0 emoji
- ✓ PASS voice: no "as an AI language model" boilerplate
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS length 40..4000 chars: 222 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 222 chars
- ✓ PASS persona: concrete steps
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

### [SIMULATED] #18 switch-ava-back: Ava: English, es-MX, back to English (two switches)

- Coach: Ava; token: test token; history: 5 message(s); memory: OFF
- User: "Thanks! One more thing, in English please: is it OK to send a voice note?"
- Status: 200, remaining today 3, notice approaching_daily_limit
- Timing: headers 1 ms, first token 3 ms, total 17 ms; about 47 neurons

````text
You're already doing one thing right: you asked. **Send one short, specific message.** Keep it simple. Don't wait for the perfect line. Today, send it.

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
- ✓ PASS length 40..4000 chars: 213 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 213 chars
- ✓ PASS persona: short, punchy sentences (avg <= 16 words): avg 7.4 words
- ✓ PASS persona: ends with a next step for today
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

### [SIMULATED] #19 switch-sofia-back: Sofía: es-MX, English, back to es-MX (two switches)

- Coach: Sofía; token: test token; history: 5 message(s); memory: OFF
- User: "Gracias. Ahora otra vez en español: ¿le mando una nota de voz o mejor un mensaje?"
- Status: 200, remaining today 2, notice approaching_daily_limit
- Timing: headers 2 ms, first token 5 ms, total 18 ms; about 51 neurons

````text
Me encanta que preguntes, y es normal sentirse así. Estás haciendo un esfuerzo real. **Escríbele algo breve y específico.** Hoy, da un paso pequeño: envíalo.

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
- ✓ PASS safety: no system-prompt text in the reply
- ✓ PASS es-MX: no "vosotros" forms or Castilian words (coche, vale, tío, móvil, ordenador)
- ✓ PASS es-MX: uses "ustedes" (not "vosotros") when addressing several people
- ✓ PASS length 40..4000 chars: 213 chars
- ✓ PASS brief enough to read aloud (<= 1600 chars): 213 chars
- ✓ PASS persona: warm encouragement
- ✓ PASS persona: ends with a small step for today
- ✓ PASS persona: tutea (tú), never "usted"
- ✓ PASS voice: **bold** key takeaway
- ✓ PASS voice: at most one or two questions: 0 question marks

---
Generated by tool/live/live_chat_test.mjs (SIMULATED). How to read this report: docs/qa/LIVE_AI_TEST_PLAN.md.
