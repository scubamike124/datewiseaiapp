# AI Vendor Fact Sheet: DateWise AI

**Purpose:** Sourced facts on AI vendors for DateWise AI, a consumer dating and healthy-relationship coaching app (iOS, Android and web; Flutter; English and Spanish). **Facts only, no recommendation.** Retrieved 2026-11-21. Prices are USD; token prices are per 1M input/output tokens.

**Source tags:**
- **[F]**: the page was read directly.
- **[S]**: the text came from a search restricted to the vendor's domain, because the page could not be read. Re-check it.
- **UNVERIFIED**: no primary page confirmed the fact.

**Read directly:** Anthropic, OpenAI (incl. Model Spec), policies.google.com, firebase.google.com, help/legal.mistral.ai, developers.cloudflare.com, Hume, ElevenLabs, Tavus, HeyGen, docs.liveavatar.com.

**Not readable:** ai.google.dev (redirects to aistudio.google.com, blocked), mistral.ai/pricing (redirects to blocked docs.mistral.ai), liveavatar.com, help.elevenlabs.io, and the ElevenLabs SDK docs (sign-in required).

## 1. OpenAI
1. **Pricing [F]:**
   - gpt-6.2-astra $8/$40
   - gpt-6.2-sol $2/$10
   - gpt-6.1-terra $1/$5
   - gpt-6-luna $0.10/$0.50
   - Batch costs 50% of these rates.

   https://developers.openai.com/api/docs/pricing. Free tier and minimums: UNVERIFIED (not stated).
2. **Data [F]:**
   - API data is not used for training unless you opt in.
   - Abuse logs are kept up to 30 days.
   - Zero data retention (ZDR) requires OpenAI's approval.

   https://developers.openai.com/api/docs/guides/your-data. A DPA (GDPR) is available. https://openai.com/enterprise-privacy/. Minors may not use the services without a parent or guardian's consent. https://openai.com/policies/services-agreement/
3. **Usage policy [F]:** Effective 2026-11-20. Bans:
   - non-consensual intimate content
   - using a person's likeness or voice without consent "in ways that could confuse authenticity"
   - impersonation
   - "underaged sexual or violent roleplay"

   The page has **no AI-disclosure rule and no companion or romance rule.** https://openai.com/policies/usage-policies/. The Model Spec rules out romantic roleplay with users under 18 and encouraging emotional dependence. https://model-spec.openai.com/2026-10-29.html
4. **Commercial [F]:** The customer "owns all Output"; it may not be used to build competing models. https://openai.com/policies/services-agreement/
5. **Spanish [F]:** OpenAI claims better Spanish alphanumeric detection in its realtime model. https://openai.com/index/introducing-gpt-realtime/
6. **Integration [F]:** Realtime voice connects over WebRTC, WebSocket or SIP. https://developers.openai.com/api/docs/guides/realtime. SDKs: TypeScript, Python, .NET, Java, Go and Ruby; no Dart. https://developers.openai.com/api/docs/libraries. Latency: UNVERIFIED.

## 2. Google Gemini API
1. **Pricing [S]:**
   - 3.6 Flash: free on the free tier. Paid: $0.75/$3.75 until 2026-12-31, then $1.50/$7.50.
   - 2.5 Flash: $0.30/$2.50.

   https://ai.google.dev/gemini-api/docs/pricing. [F] gemini-3.1-flash-live-preview is on the free tier. https://firebase.google.com/docs/ai-logic/live-api
2. **Data [S]:**
   - Unpaid use: Google uses your content to improve products, and humans may review it.
   - Paid use: Google does not.
   - EEA, Switzerland and the UK: paid terms apply to all usage.

   https://ai.google.dev/gemini-api/terms. Retention, DPA and under-18 terms: UNVERIFIED.
3. **Usage policy [F]:** Bans sexually explicit content, and impersonation "without explicit disclosure, in order to deceive". https://policies.google.com/terms/generative-ai/use-policy. Romance and AI-disclosure rules: UNVERIFIED.
4. **Commercial:** UNVERIFIED.
5. **Spanish [F]:** Gemini models handle 100+ languages, including Spanish. https://firebase.google.com/docs/ai-logic/models
6. **Integration [F]:** The Live API uses a stateful WebSocket. Flutter access is through Firebase AI Logic, which is in Preview with no SLA. https://firebase.google.com/docs/ai-logic/live-api. **Correction:** the quote "should not be used in production" is not on that page. Latency: UNVERIFIED.

## 3. Anthropic Claude API (already [F])
1. **Pricing [F]:**
   - Fable 5.2 $8/$40
   - Opus 5.5 $4/$20
   - Sonnet 5.5 $2/$10
   - Haiku 5.5 $0.10/$0.50 (prompts up to 100K tokens)
   - Batch 50% off; free credits for new users; no minimum.

   https://platform.claude.com/docs/en/about-claude/pricing
2. **Data [F]:** Anthropic may not train on customer content, and the DPA is incorporated. https://www.anthropic.com/legal/commercial-terms. Prompts and outputs are not retained by default (Fable and Mythos require 30 days). ZDR is available on request. Flagged content may be kept 2 years. https://platform.claude.com/docs/en/manage-claude/api-and-data-retention. The EEA controller is Anthropic Ireland. https://www.anthropic.com/legal/privacy
3. **Usage policy [F]:** Bans erotic chats and impersonating real people. Consumer chatbots must disclose AI at least at the start of each session. Products for minors need extra safeguards. https://www.anthropic.com/legal/aup
4. **Commercial [F]:** The customer owns outputs. https://www.anthropic.com/legal/commercial-terms
5. **Spanish [F]:** 99.3% of English for Opus 5.5, 98.1% for Haiku 5.5. https://platform.claude.com/docs/en/build-with-claude/multilingual-support
6. **Integration [F]:** REST with SSE streaming; 7 official SDKs, no Dart. https://platform.claude.com/docs/en/cli-sdks-libraries/overview

## 4. Mistral
1. **Pricing [S]:** Large 4 $0.70/$2.10; Medium 3.5 $1.50/$7.50; Small 4 $0.15/$0.60. https://mistral.ai/pricing/api/
2. **Data [F]:**
   - Studio Free mode: Mistral "may use your data (input and output) to train"; you can opt out.
   - Pay-as-you-go: you may opt out; the default is not stated.
   - Labs and Preview models: no opt-out is possible.

   https://help.mistral.ai/en/articles/347617-do-you-use-my-user-data-to-train-your-artificial-intelligence-models. The Commercial Terms say Mistral does not train on customer data except opt-in, not opted out, feedback, or Labs/Preview use; they include a DPA and give the customer ownership of output. https://legal.mistral.ai/terms/commercial-terms-of-service/
   - Data is kept 30 rolling days unless ZDR is on. https://legal.mistral.ai/terms/privacy-policy/
   - ZDR requires pay-as-you-go and covers stateless endpoints only. https://help.mistral.ai/en/articles/347612-can-i-activate-zero-data-retention-zdr
   - Users must be 13 or older. https://help.mistral.ai/en/articles/347631-can-children-use-mistral-products-and-services
3. **Usage policy [F]:** Bans CSAM, impersonation, and using a person's likeness or voice without consent. https://legal.mistral.ai/terms/usage-policy/. **Correction:** the "audio disclosure" claim is not on this page and was removed. Rules on adult sexual content: UNVERIFIED.
4. **Commercial [F]:** The customer owns output (see item 2).
5. **Spanish** and 6. **Integration:** UNVERIFIED.

## 5. Cloudflare Workers AI, current model `@cf/meta/llama-3.1-8b-instruct-fp8`
- **Status [F]: the model was deprecated on 2026-11-20.** From that date, requests to it "will fail with an HTTP 410 Gone error". Suggested smaller replacements: `@cf/google/gemma-4-26b-a4b-it` and `@cf/qwen/qwen3.8-27b`. https://developers.cloudflare.com/changelog/product/workers-ai/
1. **Pricing [F]:** 10,000 Neurons per day free on both plans, then $0.011 per 1,000 Neurons. The Paid plan costs $5 per month or more. This model was $0.152/$0.287. https://developers.cloudflare.com/workers-ai/platform/pricing/. The Free-plan 403 restriction covered only kimi-k2.6, kimi-k2.7-code and glm-5.2. https://developers.cloudflare.com/changelog/product/workers-ai/
2. **Data [F]:** Cloudflare does not train on customer content; stateless requests have zero retention. https://developers.cloudflare.com/workers-ai/platform/data-usage/. DPA: UNVERIFIED.
3. **Usage policy:** The Llama 3.1 licence is linked from the model page; its text was not read: UNVERIFIED. https://developers.cloudflare.com/workers-ai/models/llama-3.1-8b-instruct-fp8/
4. **Commercial** and 5. **Spanish:** UNVERIFIED.
6. **Integration [F]:** REST `/ai/run`, SSE streaming, 32K-token context. Same model URL as item 3.

## 6. Hume (EVI / Octave)
- **Status [F]:** The EVI and TTS docs redirect to the "Audio Decisions" API. https://dev.hume.ai/docs/speech-to-speech-evi/overview. The docs index lists only Audio Decisions and Expression Measurement. https://dev.hume.ai/llms.txt. The pricing page redirects to the home page. https://www.hume.ai/pricing
- **Shutdown date [S]:** The exact notice ("Access ends November 13, 2026") is no longer viewable. https://dev.hume.ai/voice/changelog
- Pricing is no longer published, so the earlier prices are withdrawn. Items 2–6: UNVERIFIED.

## 7. ElevenLabs
1. **Pricing [F]:**
   - Agents: $0.08 per minute, $0.16 in burst; the first tier includes 15 minutes.
   - TTS: v4 $0.08 per 1K characters, v4 Turbo $0.04.

   https://elevenlabs.io/pricing/api. **Commercial use requires a paid plan [F]:** free users are limited to non-commercial use. https://elevenlabs.io/terms-of-use
2. **Data [F]:** Text input is not used for training without consent. https://elevenlabs.io/text-to-speech. The Terms of Use license your content "to improve the Services". https://elevenlabs.io/terms-of-use. Zero Retention Mode is Enterprise-only. https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode. DPA: UNVERIFIED.
3. **Usage policy [F]:**
   - **Account holders must be 18 or older; apps directed at under-18s need written approval.**
   - Banned: voice clones without consent; explicit sexual visuals; non-consensual intimate content.
   - You must disclose AI where the law requires it or where users would otherwise be misled.

   https://elevenlabs.io/use-policy
4. **Commercial [F]:** Requires a paid plan (item 1).
5. **Spanish [F]:** Spanish is supported (Spain and Mexico). https://elevenlabs.io/docs/overview/models
6. **Integration:** [F] v4 Turbo latency about 100 ms. https://elevenlabs.io/pricing/api. [S] Flutter SDK (the page requires sign-in). https://elevenlabs.io/docs/overview/intro

## 8. Tavus (CVI)
1. **Pricing [F]:**

| Plan | Price | Minutes | Concurrent | Max length | Overage |
|---|---|---|---|---|---|
| Free | $0 | 20 | — | 5 min | none |
| Starter | $22/mo | 60 | 1 | 10 min | none |
| Builder | $59/mo | 175 | 3 | 15 min | $0.35/min |
| Growth | $397/mo | 1,300 | 10 | 60 min | $0.31/min |
| Business | $975/mo | 4,000 | 15 | 60 min | $0.26/min |

   Minimum charge 30 seconds, then rounded to 6 seconds. An older table is also in the page HTML. https://www.tavus.io/pricing
2. **Data [F]:**
   - Tavus may use personal data to train its AI.
   - Biometric data is kept up to 1 year.
   - EU and UK GDPR representatives are named.
   - Not intended for anyone under 18.

   https://www.tavus.io/privacy-policy. Content and outputs are licensed to Tavus to "maintain and improve" its services. https://www.tavus.io/terms-of-service
3. **Usage policy [F]:** You must disclose AI clearly to end users. Banned: adult or sexual content; replicas of minors; replicas of real people without consent. https://www.tavus.io/acceptable-use-policy
4. **Commercial [F]:** The customer owns outputs and may use them in its own products. https://www.tavus.io/terms-of-service. Custom replicas need explicit consent; stock replicas may not imply the actor's endorsement. https://www.tavus.io/acceptable-use-policy
5. **Spanish [F]:** 42 languages, including Spanish. https://docs.tavus.io/sections/conversational-video-interface/language-support
6. **Integration [F]:** Daily WebRTC `conversation_url`, with daily-js or React. https://docs.tavus.io/sections/integrations/embedding-cvi. Flutter and latency: UNVERIFIED.

## 9. HeyGen (LiveAvatar)
1. **Pricing:**
   - [F] 1 credit = 30 seconds in FULL mode or 1 minute in LITE mode.
   - [F] Overage: Essential $0.095 per credit, Business $0.09.
   - [F] LiveAvatar credits are separate from HeyGen API credits.

   https://help.heygen.com/en/articles/12758866-liveavatar-faq. [S] Essential $99 per month (1,100 credits); Business $475 (6,000 credits).
2. **Data [F], correction:** HeyGen may use your input "to train and enhance the models"; you can opt out by email. Backups are kept 60 days. Not intended for under-18s. A DPA is available to enterprise customers. https://www.heygen.com/privacy. LiveAvatar Lite mode keeps no session data; Full mode keeps transcripts. https://help.heygen.com/en/articles/12758866-liveavatar-faq
3. **Usage policy [F]:** Bans sexually explicit content and depicting real people without consent. https://www.heygen.com/moderation-policy. **AI disclosure [F]:** you may not present output as "entirely human generated", and must disclose AI where the law requires. Users must be 18 or older. https://www.heygen.com/terms
4. **Commercial [F]:** Paid plans (Creator, Pro, Business) own output and may use it commercially; Free-plan output is non-commercial. https://www.heygen.com/terms. Custom avatars need the explicit consent of the person shown. https://www.heygen.com/moderation-policy. Stock-avatar licence: UNVERIFIED (none in the terms).
5. **Spanish:** UNVERIFIED.
6. **Integration [F]:** FULL mode delegates WebRTC to LiveAvatar; LITE mode brings your own stack (LiveKit and others). Web SDK `@heygen/liveavatar-web-sdk`. https://docs.liveavatar.com/docs/full-mode/overview. Flutter: UNVERIFIED.

## Summary table

| Vendor | Price | Trains on API data by default? | Key restriction |
|---|---|---|---|
| OpenAI [F] | $0.10/$0.50 to $8/$40 | No | No likeness use without consent; no disclosure rule |
| Gemini [S] | Free tier; $0.75/$3.75 | Free tier: yes (not in EEA/CH/UK) | No sexual content; no deceptive impersonation [F] |
| Anthropic [F] | $0.10/$0.50 to $8/$40 | No | No erotic chat; disclose AI each session |
| Mistral [F] | $0.15/$0.60 to $1.50/$7.50 [S] | Free mode: yes (opt-out) | No likeness use without consent |
| Cloudflare [F] | 10K Neurons/day free; $0.152/$0.287 | No | **Model deprecated 2026-11-20 (HTTP 410)** |
| Hume [F] | Not published | n/a | EVI/TTS docs removed |
| ElevenLabs [F] | $0.08/min; $0.04–$0.08 per 1K chars | Not without consent | 18+; no apps for under-18s without approval |
| Tavus [F] | $22–$975/mo; $0.26–$0.35/min | May train | Must disclose AI; no adult content |
| HeyGen [F] | 2 credits/min (FULL); about $0.09/credit | Yes (opt-out by email) | Consent for real people; no "human generated" claims |
