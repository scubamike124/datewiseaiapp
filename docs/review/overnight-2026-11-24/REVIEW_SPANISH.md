# DateWise AI: Mexican Spanish review (2026-11-24)

Reviewer: independent read-only pass. Repo not edited.

Scope: `lib/l10n/app_es.arb` vs `app_en.arb`, `lib/content/legal_text.dart` (kPrivacyPolicyEs, kTermsOfServiceEs), `lib/content/support_text.dart` (kSupportPageEs), `backend/coach_prompts.js` + `lib/models/coach.dart` (Sofía, Diego), `lib/services/mock_ai_service.dart` (demo coach), `lib/dev/review_mode.dart`, screenshots `preview/shots/es-*.jpg` (11 screens).

## Overall verdict

Good quality. The Spanish reads natural for Mexico, consistently uses **tú**, uses the correct iOS es-MX names (Configuración, Cuenta de Apple, Privacidad y seguridad, Contenido leído, Mantén presionado), has correct accents/¿¡ and no encoding damage.

Automated checks:
- Keys: 0 missing, 0 extra (every EN key exists in ES).
- Placeholders: every `{name}`, `{price}`, `{perMonth}`, `{count}`, `{daily}` etc. matches EN. The only differences are ICU `select`/`plural` branches (`{gender, select, female{lista} other{listo}}`, `{count, plural, ...}`), which are correct and intended.
- Strings identical to EN (`Coaching`, `Chat`, `Coaches`, `DateWise Premium`, `appTitle`, `appVersion`, `coachSays`): all acceptable; "chat", "coach" and "coaching" are common anglicisms in Mexico.
- No mojibake (Ã, Â, â€) in any Spanish file. No Spain-only words (vosotros, vale, móvil, ordenador, coger, guay) and no "usted".
- Subscription disclosure: complete. It says monthly (`Mensual · renovación automática`), auto-renewing (`se renueva automáticamente cada mes`), price from the App Store (`Precio indicado por el App Store`; `paywallDisclosureNoPrice`), charge to the Cuenta de Apple, the 24-hour cancellation window, and cancel anytime (`Cancela cuando quieras en Configuración › [tu nombre] › Suscripciones`). The Terms and Support text match.
- Screenshots: no untranslated buttons and no clipped text at the captured width (~393 pt). One item is tight (see #1).

No High (blocking) issues. Severity: **Med** = fix before the owner's Spanish test / release. **Low** = polish.

## Findings

| # | Location | Current text | Problem | Proposed replacement | Severity |
|---|---|---|---|---|---|
| 1 | ARB `chatWith` / `coach.dart` chatLabel; shots es-coaches, es-onboarding-4 | `Chatear con {name}` | The pill button almost touches the card edge at 393 pt (onboarding has wider margins). On iPhone SE/mini (375 pt) or with larger Dynamic Type it will likely clip or overflow. | Layout first: let the label scale down or ellipsize, and test at 375 pt and 320 pt. A slightly shorter copy also helps: `Chatea con {name}` | Med |
| 2 | Mock coach `spanishReply`, photo branch (mock_ai_service.dart:59) | `Envíame tus fotos y te digo cuáles mantener.` | Promises photo upload, which the app does not have (`photoNoLongerAvailable`; the EN mock has no photo branch). "Mantener" is also a literal translation of "keep". | `Descríbeme tus fotos (qué se ve en cada una) y te digo cuáles dejar. La primera debe mostrar **tu cara con buena luz** y una sonrisa natural.` | Med |
| 3 | Sofía/Diego prompts (`coach_prompts.js` + `coach.dart` styleRules; mirrored by a test) | `reconoces el esfuerzo del usuario…`, `tuteas al usuario` | The user's gender is unknown. Llama will default to masculine agreement ("¿estás nervioso?", "bienvenido"), which feels off for women users. | Add to both styles: `No sabes el género del usuario: usa formas neutras (por ejemplo "te ponen nervios", "qué gusto que estés aquí") hasta que la persona lo indique.` | Med |
| 4 | `languageRule('es')` in coach_prompts.js | `never "vosotros" or Spain-only words such as "móvil", "ordenador" or "vale"` | Target users are in Mexico. The list leaves out "coger" (vulgar in Mexico, and Llama uses it for "take"), "guay", "tío/tía", "mola" and "quedar (con alguien)". | `…never "vosotros" or Spain-only words such as "móvil", "ordenador", "vale", "guay", "tío/tía", "mola", "quedar con alguien" and never "coger" (use "tomar", "agarrar"). Prefer vocabulary natural in Mexico (celular, salir con alguien, ligar).` | Med |
| 5 | System prompt safety line (shared) | `urge them to contact local emergency services or a crisis line` | Spanish coaches give no Mexico-specific help number. | For `lang === 'es'` add: `En México: 911 (emergencias) y Línea de la Vida 800 911 2000 (24 h).` (Owner: verify the number before shipping.) | Med |
| 6 | Privacy (ES and EN): identity / ARCO rights | `Según dónde vivas, puedes tener derecho a acceder, corregir o eliminar…`; `Al usar la app, aceptas este procesamiento.` | Legal, not translation. Mexico's privacy law (LFPDPPP 2025) expects an "aviso de privacidad" that names the controller and its address, explains how to exercise ARCO rights, and covers international transfers. The text has none of these. | Owner/legal review. Possible wording: `Responsable: [nombre legal], [domicilio]. Para ejercer tus derechos ARCO (acceso, rectificación, cancelación u oposición) escribe a support@datewiseai.com.` | Med (legal review) |
| 7 | ARB `legalTranslationNote` | `…prevalece la versión en inglés.` | Mexican consumer protection rules may require Spanish for consumer terms, so "English prevails" may not be enforceable against Mexican consumers. | Legal review only. No wording change proposed. | Low (legal review) |
| 8 | ARB `welcomeBody` (es-welcome shot) | `…de un coach que te escucha.` | Shown next to Sofía's female portrait, and the masculine "un coach" reads as a mismatch. | `Ayuda honesta con tu perfil, tus mensajes y tu primera cita. Tu coach te escucha.` | Low |
| 9 | ARB `quickPracticePrompt` | `Practiquemos una conversación. Tú haces de mi match y yo respondo.` | "Hacer de" (play a role) sounds peninsular. A Mexican speaker would say "haz de cuenta" or "tú eres". | `Practiquemos una conversación. Tú eres mi match y yo te respondo.` | Low |
| 10 | ARB `aiConsentBody`; Privacy "Tu permiso…" | `tus mensajes (escritos o dichos en voz alta, como texto)` | Literal and awkward. | `tus mensajes (escritos o dictados por voz, ya convertidos en texto)` (use the same phrase in kPrivacyPolicyEs) | Low |
| 11 | ARB `findTable` / `findTableSemantics`; Privacy "Buscar mesa" | `Buscar mesa` / `Buscar mesa cerca. Abre Apple Maps.` | "Buscar mesa" reads like furniture. The action searches restaurants. In Spanish iOS the app is called "Mapas". | `Buscar restaurante` / `Buscar restaurantes cerca. Abre Mapas de Apple.` (update the Privacy bullet to match) | Low |
| 12 | ARB `tapToTalkHint` (VoiceOver) | `Toca dos veces para empezar a hablar y otra vez para enviar` | "Otra vez" is ambiguous (one tap, or another double tap?). | `Toca dos veces para empezar a hablar y vuelve a tocar dos veces para enviar` | Low |
| 13 | ARB `chatErrorBusy` | `…muchos mensajes en este momento. Inténtalo de nuevo en un momento.` | "Momento" is repeated. | `Tu coach está recibiendo muchos mensajes ahora mismo. Inténtalo de nuevo en un momento. Tu mensaje está guardado.` | Low |
| 14 | ARB `paywallFairUse` | `Verás un aviso cerca de un límite; al alcanzarlo, …` | Literal. | `Uso justo: hasta {daily} respuestas del coach al día y {monthly} al mes, con un máximo de {perMinute} por minuto y {concurrent} a la vez. Los mensajes escritos y hablados cuentan igual. Te avisaremos cuando estés cerca de un límite; al alcanzarlo, el chat se pausa hasta el día siguiente (00:00 UTC) o el mes siguiente.` | Low |
| 15 | ARB `coachLimitDaily` (and fair-use "00:00 UTC") | `Se restablece a la medianoche (UTC).` | Midnight UTC is 6:00 p. m. in Mexico City (no daylight saving time since 2022). Users will read it as their own midnight. | Optional: `Se restablece a las 00:00 UTC (6:00 p. m. en la Ciudad de México).` (or show local time computed in code) | Low |
| 16 | ARB `paywallDisclosure`, `paywallDisclosureNoPrice`; Terms | `a menos que la canceles al menos 24 horas antes…` | "a menos… al menos" sounds clunky. The meaning is correct. | `…salvo que la canceles al menos 24 horas antes de que termine el período actual…` (keep `{perMonth}` and `{price}` exactly) | Low |
| 17 | ARB `daysTotal` | `En total, hablaste con un coach {count, plural, =1{1 día} other{{count} días}}.` | Awkward word order for a total. | `En total, has hablado con un coach {count, plural, =1{1 día} other{{count} días}}.` | Low |
| 18 | ARB `progressFootnote` | `…Las marcas se reinician cada lunes.` | "Marcas" can be read as "brands". | `Marca los pendientes del plan en Inicio. Se desmarcan cada lunes.` | Low |
| 19 | ARB `statPlanDone` (es-progress shot) | `…pasos del plan completados esta semana` | Wraps to 3 lines at 393 pt and is likely 4 on SE, which makes this card taller than its neighbours. | `{count, plural, =1{paso completado esta semana} other{pasos completados esta semana}}` | Low |
| 20 | ARB `planItemProfile`, `planPromptProfile`, Sofía starter | `Reescribe tu biografía con {name}` / `Reescribe mi biografía de citas.` | "Biografía" is formal. Mexican dating-app users say "bio" or "descripción". | `Reescribe tu bio con {name}` / `Reescribe la bio de mi perfil de citas.` | Low |
| 21 | ARB `homeReady` / `homeResume` | `{name} está {gender, select, female{lista} other{listo}} cuando tú quieras.` | It is understandable, but "para cuando" is the natural form. | `{name} está {gender, select, female{lista} other{listo}} para cuando tú quieras. Tu coach con IA, a cualquier hora.` (do the same in homeResume, keeping `{title}`) | Low |
| 22 | Mock coach, date branch | `Avisa a un amigo de dónde estarás y llega por tu cuenta.` | Stiff, and "un amigo" is masculine. | `Avísale a alguien de confianza dónde vas a estar y llega por tu cuenta.` | Low |
| 23 | Diego starter (coach.dart) | `Planea una primera cita` | As a message the user sends, it reads like a bare order. | `Ayúdame a planear una primera cita` | Low |
| 24 | Support `kSupportPageEs` (Legal) vs Terms | `asesoramiento profesional` vs Terms `asesoría profesional` | Inconsistent; "asesoría" is the usual Mexican term. | `…sus sugerencias no son asesoría profesional.` | Low |
| 25 | `FairUse.format` (es) | 4 digits without a separator; larger numbers grouped with a space (`15 000`) | Fine today (150 / 1500). If a limit reaches 5+ digits, Mexico (and Apple's es-MX locale) writes `15,000`. | Use `,` grouping for es-MX if the limits ever exceed 9999. | Low |
| 26 | Review build paywall (es-paywall shot) | `$19.99` | Fake-store USD price only. Real builds get the localized price from StoreKit (e.g. MXN). Not a bug; noted so nobody files it. | None | Info |

## Not issues (checked)
- tú/usted: consistently tú everywhere (UI, legal, support, prompts, mock).
- Gendered ICU selects (`lista/listo`, `una/un coach`) are correct for Sofía (female) and Diego (male).
- `welcomePortrait` hard-codes "una coach". That is correct because the welcome screen only ever shows Sofía or Ava.
- iOS path names (Configuración › [tu nombre] › Suscripciones; Accesibilidad › Contenido leído › Voces; Privacidad y seguridad) match es-MX iOS. Paulina and Juan are real es-MX system voices.
- Spanish typography is correct: `100 %`, `p. ej.:`, `›`, ` ` in "con IA".

Note: any change to Sofía/Diego style rules must be made in both `backend/coach_prompts.js` and `lib/models/coach.dart` (`backend/cost_guard.test.mjs` checks that they match).
