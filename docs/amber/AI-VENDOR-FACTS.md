# AI Vendor Fact Sheet: DateWise AI

**Purpose:** Sourced facts on AI vendors for DateWise AI, a consumer dating and healthy-relationship coaching app (iOS, Android and web; Flutter; English and Spanish). **Facts only, no recommendation.** Retrieved 2026-11-21. Prices are USD; token prices are per 1M input / output tokens.

**Source tags:** **[F]** means the page was fetched and read directly. **[S]** means the text came from a web search restricted to the vendor's own domain; the page itself could not be opened because this session's network allowed only Anthropic hosts. Re-check every [S] fact on the live page. **UNVERIFIED** means no primary page confirmed the fact.

## 1. OpenAI
1. **Pricing [S]:** GPT-6.2 Astra $8/$40. GPT-6.2 Sol $2/$10. GPT-6 Luna $0.10/$0.50. Batch requests cost 50% of these rates. Above 272K input tokens, input costs 2x and output 1.5x. https://developers.openai.com/api/docs/pricing. Free tier and minimums: UNVERIFIED.
2. **Data [S]:** API data is not used for training unless you opt in. Abuse logs are kept 30 days. Stateful endpoints keep data until you delete it. Zero data retention (ZDR) needs OpenAI's approval. https://developers.openai.com/api/docs/guides/your-data. API inputs and outputs may be retained up to 30 days. https://openai.com/enterprise-privacy/. DPA, GDPR and under-18 terms: UNVERIFIED.
3. **Usage policy:** The Usage Policies page was not found: UNVERIFIED. The Model Spec governs model behaviour [S]: no romantic roleplay or romantic pairing for users under 18; no encouraging emotional dependence. https://model-spec.openai.com/2026-10-29.html. AI-disclosure rule: UNVERIFIED.
4. **Commercial [S]:** The customer "owns all Output". Output may not be used to build competing models. https://openai.com/policies/services-agreement/
5. **Spanish [S]:** OpenAI claims better Spanish alphanumeric detection in its realtime model. https://openai.com/index/introducing-gpt-realtime/
6. **Integration [S]:** Realtime voice connects over WebRTC (browser) or WebSocket (server), through the TypeScript Agents SDK. https://developers.openai.com/api/docs/guides/realtime. Dart support and latency: UNVERIFIED.

## 2. Google Gemini API
1. **Pricing [S]:** Gemini 3.6 Flash is free on the free tier. Paid, it costs $0.75/$3.75 through 2026-12-31, then $1.50/$7.50. Gemini 2.5 Flash costs $0.30/$2.50. Flash-Lite and Gemma 4 also have free access. Free-tier limits are per-model rate limits. https://ai.google.dev/gemini-api/docs/pricing. gemini-3.1-pro-preview costs $2/$12 and has no free tier. https://ai.google.dev/gemini-api/docs/gemini-3. Price of "Gemini 4 Argon": UNVERIFIED (seen only on a "What's new" page).
2. **Data [S]:** On unpaid services, Google uses your content to improve its products, human reviewers may read it, and Google says "Do not submit sensitive, confidential, or personal information." Paid services do not use it. In the EEA, Switzerland and the UK, paid-service terms apply to all usage, including the free quota. https://ai.google.dev/gemini-api/terms. Retention, DPA and under-18 terms: UNVERIFIED.
3. **Usage policy [S]:** Sexually explicit content is prohibited. Impersonating a person without disclosure, in order to deceive, is prohibited. https://policies.google.com/terms/generative-ai/use-policy. Automated scanning enforces the policy, up to account closure. https://ai.google.dev/gemini-api/docs/usage-policies. Romance and AI-disclosure rules: UNVERIFIED.
4. **Commercial:** UNVERIFIED.
5. **Spanish:** UNVERIFIED.
6. **Integration [S]:** The Live API runs over WebSocket. https://ai.google.dev/gemini-api/docs/live-api. Flutter/Dart support comes through Firebase AI Logic; its Live API is in Public Preview with no SLA and "should not be used in production apps." https://firebase.google.com/docs/ai-logic/live-api. Latency: UNVERIFIED.

## 3. Anthropic Claude API
1. **Pricing [F]:** Fable 5.2 $8/$40. Opus 5.5 $4/$20. Sonnet 5.5 $2/$10. Haiku 5.5 $0.10/$0.50 (for prompts up to 100K tokens). Batch requests get 50% off. New users get free credits (no amount stated). No minimum is listed. https://platform.claude.com/docs/en/about-claude/pricing
2. **Data [F]:** "Anthropic may not train models on Customer Content from Services." The DPA is incorporated by reference. https://www.anthropic.com/legal/commercial-terms. Prompts and outputs are not retained by default, except that Fable and Mythos models require 30-day retention. ZDR is available on request; under ZDR, browser calls are blocked. Flagged content may be kept up to 2 years. https://platform.claude.com/docs/en/manage-claude/api-and-data-retention. The EEA controller is Anthropic Ireland. https://www.anthropic.com/legal/privacy
3. **Usage policy [F]:** "Erotic chats" are prohibited. Impersonating real individuals is prohibited, except disclosed parody or fiction. Consumer chatbots must disclose AI at least at the start of each session. Products for minors (under 18) need extra safeguards. There is no companion-specific rule. https://www.anthropic.com/legal/aup
4. **Commercial [F]:** The customer "owns its Outputs" and may serve its own end users. https://www.anthropic.com/legal/commercial-terms
5. **Spanish [F]:** Spanish scores are 99.3% of English (Opus 5.5) and 98.1% (Haiku 5.5). https://platform.claude.com/docs/en/build-with-claude/multilingual-support
6. **Integration [F]:** REST API with streaming. Official SDKs cover 7 languages, not Dart. https://platform.claude.com/docs/en/cli-sdks-libraries/overview. Latency: UNVERIFIED.

## 4. Mistral
1. **Pricing [S]:** Large 4 $0.70/$2.10. Medium 3.5 $1.50/$7.50. Small 4 $0.15/$0.60. https://mistral.ai/pricing/api/. Free tier: UNVERIFIED.
2. **Data [S]:** A training opt-out toggle exists; the default setting is UNVERIFIED. https://help.mistral.ai/en/articles/455207-can-i-opt-out-of-my-input-or-output-data-being-used-for-training. Inputs and outputs are kept 30 days unless ZDR is active. https://legal.mistral.ai/terms/privacy-policy/. ZDR is stateless-only and approved case by case. https://help.mistral.ai/en/articles/347612-can-i-activate-zero-data-retention-zdr. Users must be 13 or older. https://help.mistral.ai/en/articles/347631-can-children-use-mistral-products-and-services
3. **Usage policy [S]:** Impersonation is banned. Using a person's likeness or voice without consent is banned. AI audio must be disclosed where the law requires. https://legal.mistral.ai/terms/usage-policy/. Rules on sexual content: UNVERIFIED.
4. **Commercial**, 5. **Spanish**, 6. **Integration:** UNVERIFIED.

## 5. Cloudflare Workers AI, current model `@cf/meta/llama-3.1-8b-instruct-fp8`
1. **Pricing [S]:** 10,000 Neurons per day free, then $0.011 per 1,000 Neurons. This model costs $0.152 per 1M input tokens and $0.287 per 1M output tokens. https://developers.cloudflare.com/workers-ai/platform/pricing/. Whether this model is blocked on the Free plan: UNVERIFIED. https://developers.cloudflare.com/changelog/product/workers-ai/
2. **Data [S]:** Cloudflare does not train on customer content. Stateless requests have zero retention. https://developers.cloudflare.com/workers-ai/platform/data-usage/. DPA: UNVERIFIED.
3. **Usage policy [S]:** Third-party models carry their own licences. https://developers.cloudflare.com/workers-ai/platform/data-usage/. Llama licence and AUP: UNVERIFIED.
4. **Commercial**, 5. **Spanish**, 6. **Integration:** UNVERIFIED.

## 6. Hume (EVI / Octave)
- **Status [S]:** Hume says EVI and TTS API access "ends November 13, 2026," and account data is deleted after that. https://dev.hume.ai/voice/changelog. Whether the APIs still work today: UNVERIFIED.
1. **Pricing (may be stale) [S]:** Free plan has 5 EVI minutes. Paid plans cost $0.07 down to $0.04 per minute. https://www.hume.ai/pricing. Free and Starter plans are non-commercial only. https://dev.hume.ai/voice/docs/text-to-speech-tts/faq
2–6. UNVERIFIED (not researched further because of the sunset).

## 7. ElevenLabs
1. **Pricing [S]:** Agents cost $0.08 per minute, with 15 free minutes. TTS costs $0.04–$0.08 per 1K characters. https://elevenlabs.io/pricing/api. Which plan grants commercial rights: UNVERIFIED.
2. **Data [S]:** Text is not used for training without consent. https://elevenlabs.io/text-to-speech. Zero Retention Mode is Enterprise-only. https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode. DPA: UNVERIFIED.
3. **Usage policy [S]:** Prohibited: cloning a voice without consent; recordings of under-18s; a real minor's likeness. https://elevenlabs.io/use-policy. Rules on sexual content: UNVERIFIED.
4. **Commercial [S]:** Voice clones require verified consent. https://elevenlabs.io/docs/eleven-creative/voices/voice-cloning
5. **Spanish [S]:** Multilingual v2 supports Spanish (Spain and Mexico). https://elevenlabs.io/docs/overview/models
6. **Integration [S]:** An official Flutter SDK exists for Agents. https://elevenlabs.io/docs/overview/intro. Flash v2.5 latency is about 100 ms. https://elevenlabs.io/docs/overview/models

## 8. Tavus (CVI)
1. **Pricing [S]:** Free plan has 20–25 minutes. Paid plans start at $22 or $59 per month. Overage is $0.26–$0.37 per minute (the page showed conflicting versions). https://www.tavus.io/pricing. Exact figures: UNVERIFIED.
2. **Data:** UNVERIFIED.
3. **Usage policy [S]:** Replicas of real people require consent. End users must be told when they are talking to AI. https://www.tavus.io/acceptable-use-policy
4. **Commercial [S]:** Custom replicas need the subject's consent. Stock replicas may not imply the actor endorses you. https://www.tavus.io/acceptable-use-policy. Licence text: UNVERIFIED.
5. **Spanish [S]:** Supported (42 languages). https://docs.tavus.io/sections/conversational-video-interface/faq
6. **Integration [S]:** Runs on Daily WebRTC rooms. https://docs.tavus.io/sections/integrations/embedding-cvi. Flutter and latency: UNVERIFIED.

## 9. HeyGen (LiveAvatar)
1. **Pricing [S]:** FULL mode uses 2 credits per minute, LITE mode 1. The Essential plan costs $99 per month for 1,100 credits. https://help.heygen.com/en/articles/12758866-liveavatar-faq
2. **Data [S]:** Models are trained on user data only with consent. https://www.heygen.com/ethics. Retention and DPA: UNVERIFIED.
3. **Usage policy [S]:** Avatars of other people require their consent. https://www.heygen.com/moderation-policy. Rules on sexual content and AI disclosure: UNVERIFIED.
4. **Commercial [S]:** A Digital Twin requires a consent video. https://www.heygen.com/moderation-policy. Stock avatars need no agreement. https://developers.heygen.com/docs/models/avatar-6. Stock licence: UNVERIFIED.
5. **Spanish:** UNVERIFIED.
6. **Integration [S]:** WebRTC is managed by LiveAvatar in FULL mode or runs through LiveKit in LITE mode. The Web SDK is JavaScript. https://docs.liveavatar.com/docs/full-mode/overview. Flutter: UNVERIFIED.

## Summary table

| Vendor | Price | Trains on API data by default? | Key restriction |
|---|---|---|---|
| OpenAI [S] | $0.10/$0.50 to $8/$40 | No | Under-18 romance limits (Model Spec) |
| Gemini [S] | Free tier; $0.75/$3.75 | Free tier: yes (not in EEA/CH/UK); paid: no | No sexual content; no deceptive impersonation |
| Anthropic [F] | $0.10/$0.50 to $8/$40 | No | No erotic chat; disclose AI each session |
| Mistral [S] | $0.15/$0.60 to $1.50/$7.50 | UNVERIFIED | No likeness use without consent |
| Cloudflare [S] | 10K Neurons/day free; $0.152/$0.287 | No | Llama licence applies |
| Hume [S] | $0.04–$0.07/min | UNVERIFIED | APIs sunset 2026-11-13 |
| ElevenLabs [S] | $0.08/min | No without consent | No voice clone without consent |
| Tavus [S] | $0.26–$0.37/min | UNVERIFIED | Consent; disclose AI |
| HeyGen [S] | About $0.09–$0.19/min | Only with consent | Consent for avatars |
