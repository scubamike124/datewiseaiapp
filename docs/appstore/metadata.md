# DateWise AI 2.0.0: App Store metadata

Existing App Store record: **DateWise AI - Dating Coach**, Apple ID `6780110141`,
bundle id `com.datewise.datewiseAi`. Version 2.0.0 is an update to that app:
do **not** create a new app record.

Everything here describes what the v2 app actually does. There are no
statistics, ratings, testimonials or results claims; keep it that way.

Items marked **OWNER** need the owner's decision or confirmation.
The ordered owner steps, with every answer filled in, are in
[SUBMISSION_READY.md](SUBMISSION_READY.md); it is also the copy-paste source
for the App Review notes.

Locales: English (U.S.) is the primary language. Spanish text is written for
**Spanish (Mexico)**; it can be copied to Spanish (Spain) if the owner wants
both. The app's interface follows the device language (English or Spanish)
and can be changed in You › Language; Ava and Ethan coach in English, Sofía
and Diego in Spanish.

---

## 1. App information

| Field | English (U.S.) | Spanish (Mexico) |
|--|--|--|
| Name (≤30) | DateWise AI | DateWise AI |
| Subtitle (≤30) | Your AI dating coach | Tu coach de citas con IA |
| Primary category | Lifestyle | Lifestyle (Estilo de vida) |
| Secondary category | none (optional: Social Networking is **not** recommended; the app has no social features) | |
| Support URL | `https://datewiseai.com/terms-of-service` (no support page exists in this repository; the Terms page ends with a Contact section showing support@datewiseai.com, which meets Apple's "easy way to contact you". Keep the record's current Support URL instead if it is live and shows contact details) | same |
| Marketing URL (optional) | Leave blank (optional field; `datewiseai.com`'s home page is not published from this branch) | same |
| Privacy Policy URL | `https://datewiseai.com/privacy-policy` (hard-coded in the app, `lib/app_links.dart`; it must serve the v2 text, "Last updated: November 23, 2026", before submission: see "Where the legal pages are hosted" below) | same |
| Copyright | **OWNER:** `2026 <legal owner name>` | same |

**Where the legal pages are hosted.** The app opens
`https://datewiseai.com/privacy-policy` and `/terms-of-service`. Those clean
URLs work only on a host that applies `web/.htaccess` (Apache, e.g. GoDaddy,
where `datewiseai.com` is believed to be hosted) or `web/_redirects`
(Netlify). The repository's own publisher, `.github/workflows/deploy.yml`, is
manual-only, publishes only `main`, and targets GitHub Pages under
`/<repo>/`, where neither rule file applies (only `/privacy.html` and
`/terms.html` would work, and the app's URLs would 404). `main` already
has the v2 legal pages; only publishing them to `datewiseai.com` remains. The
owner publishes `web/privacy.html`,
`web/privacy-es.html`, `web/terms.html`, `web/terms-es.html` and the rewrite
rules from `web/.htaccess` to the `datewiseai.com` host by hand, then opens
both URLs in Safari. Not checked live from here (the sandbox cannot reach the
site).

Name note: the store record is currently named "DateWise AI - Dating Coach".
Changing it to "DateWise AI" is optional; the subtitle carries "dating coach".

### Promotional text (≤170, can change without a new build)

**EN** (145 chars)
> Meet four AI dating coaches: Ava and Ethan in English, Sofía and Diego in Spanish. Get help with your profile, your messages and your first date.

**ES** (149 chars)
> Conoce a cuatro coaches de citas con IA: Ava y Ethan en inglés, Sofía y Diego en español. Recibe ayuda con tu perfil, tus mensajes y tu primera cita.

### Keywords (≤100 bytes, comma separated, no spaces)

**EN** (96): `advice,openers,profile,bio,first date,texting,flirting,conversation,relationship,match,tips,chat`

**ES** (97 bytes): `consejos,ligar,primer mensaje,perfil,biografía,primera cita,conversación,pareja,amor,match,chat`

(Do not repeat the app name or category in keywords; Apple ignores them.
Do not add competitor or other app names.)

### Description (≤4000; EN 2,322 and ES 2,578 characters)

**EN**

> DateWise AI is a dating coach powered by AI. Pick a coach, tell them what you are working on, and get honest, practical help with your dating life.
>
> FOUR AI COACHES
> • Ava: a direct, supportive confidence coach (English)
> • Ethan: a practical, laid-back strategy coach (English)
> • Sofía: a warm, motivating confidence coach (Spanish)
> • Diego: a practical, honest relationship coach (Spanish)
> Switch coaches any time. Each coach keeps its own conversations on your device.
>
> WHAT YOU CAN DO
> • Improve your dating profile and bio
> • Get openers and replies you can adapt to your own words
> • Work out what to say when a conversation stalls
> • Plan a first date that is simple and safe
> • Follow a short weekly plan and see your progress
>
> VOICE PRACTICE
> Hold the talk button to speak to your coach and hear replies read aloud. Speech recognition runs on your device; only the text of your message is sent.
>
> PRIVACY
> • No account and no sign-in
> • Conversations, your plan and progress are stored on your device
> • Your messages are sent to our AI provider only to generate a reply
> • Coach memory is off unless you turn it on
> • No ads, no analytics, no tracking
> • Delete your conversations or all your data from the You tab
>
> IMPORTANT
> DateWise AI is for adults 18+. The coaches are AI, not people, and they can make mistakes. Their advice is not professional, medical, legal or mental health advice. Always meet new people in public places and put your safety first.
>
> DATEWISE PREMIUM
> Chatting with the coaches requires DateWise Premium, an auto-renewing monthly subscription ($19.99/month in the U.S.; local prices vary). Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel it in Settings › [your name] › Subscriptions.
>
> Fair use: DateWise Premium includes generous everyday coaching for personal use, up to 150 coach replies a day and 1,500 a month (at most 12 a minute and 2 at a time). Typed and spoken messages count the same. You will see a notice in the chat when you are close to a limit. When a limit is reached, chat pauses until the next day (00:00 UTC) or the next month.
>
> Terms of Use: https://datewiseai.com/terms-of-service
> Privacy Policy: https://datewiseai.com/privacy-policy

**ES**

> DateWise AI es un coach de citas con inteligencia artificial. Elige un coach, cuéntale en qué estás trabajando y recibe ayuda sincera y práctica para tu vida amorosa.
>
> CUATRO COACHES CON IA
> • Ava: coach de autoconfianza, directa y comprensiva (inglés)
> • Ethan: coach de estrategia, práctico y relajado (inglés)
> • Sofía: coach de autoconfianza, cálida y motivadora (español)
> • Diego: coach de relaciones, práctico y honesto (español)
> Cambia de coach cuando quieras. Cada coach guarda sus propias conversaciones en tu dispositivo.
>
> QUÉ PUEDES HACER
> • Mejorar tu perfil y tu biografía
> • Recibir primeros mensajes y respuestas que puedes adaptar a tus palabras
> • Saber qué escribir cuando una conversación se enfría
> • Planear una primera cita sencilla y segura
> • Seguir un plan semanal corto y ver tu progreso
>
> PRÁCTICA POR VOZ
> Mantén presionado el botón para hablar con tu coach y escucha sus respuestas en voz alta. El reconocimiento de voz funciona en tu dispositivo; solo se envía el texto de tu mensaje.
>
> PRIVACIDAD
> • Sin cuenta y sin inicio de sesión
> • Tus conversaciones, tu plan y tu progreso se guardan en tu dispositivo
> • Tus mensajes se envían a nuestro proveedor de IA solo para generar la respuesta
> • La memoria del coach está apagada salvo que la actives
> • Sin anuncios, sin analíticas, sin rastreo
> • Borra tus conversaciones o todos tus datos desde la pestaña Tú
>
> IMPORTANTE
> DateWise AI es para mayores de 18 años. Los coaches son IA, no personas, y pueden equivocarse. Sus consejos no son asesoría profesional, médica, legal ni de salud mental. Conoce a personas nuevas siempre en lugares públicos y prioriza tu seguridad.
>
> DATEWISE PREMIUM
> Para chatear con los coaches necesitas DateWise Premium, una suscripción mensual con renovación automática (US$19.99 al mes en EE. UU.; el precio local puede variar). El pago se carga a tu Cuenta de Apple al confirmar la compra. La suscripción se renueva automáticamente salvo que la canceles al menos 24 horas antes de que termine el período actual. Adminístrala o cancélala en Configuración › [tu nombre] › Suscripciones.
>
> Uso justo: DateWise Premium incluye coaching diario generoso para uso personal, hasta 150 respuestas del coach al día y 1500 al mes (con un máximo de 12 por minuto y 2 a la vez). Los mensajes escritos y hablados cuentan igual. Verás un aviso en el chat cuando estés cerca de un límite. Al alcanzar un límite, el chat se pausa hasta el día siguiente (00:00 UTC) o el mes siguiente.
>
> Términos de uso: https://datewiseai.com/terms-of-service
> Política de privacidad: https://datewiseai.com/privacy-policy

### What's New in 2.0.0 (≤4000; EN 171, ES 180 characters)

**EN**
> DateWise AI 2.0 is a full redesign: four AI coaches (two in English, two in Spanish), voice practice, a weekly plan, and DateWise Premium, one simple monthly subscription.

**ES**
> DateWise AI 2.0 es un rediseño completo: cuatro coaches con IA (dos en inglés y dos en español), práctica por voz, un plan semanal y DateWise Premium, una sola suscripción mensual.

---

## 2. Age rating questionnaire (App Store Connect › App Information › Age Rating)

Target result: **18+** (Apple's current top tier; older App Store Connect
versions call it 17+). The app is a dating coach for adults and has an 18+
confirmation in onboarding.

| Question | Answer |
|--|--|
| Parental controls | No |
| Age assurance | No (the app asks users to confirm they are 18+; it does not verify age) |
| Unrestricted web access | No (links open only the privacy policy, terms, support email and an Apple Maps search) |
| User-generated content | No (no content is shared with other users) |
| Messaging and chat (with other people) | No (chat is with an AI coach only) |
| Advertising | No |
| Cartoon or fantasy violence / realistic violence / prolonged graphic violence | None |
| Profanity or crude humor | Infrequent/Mild (the AI may echo the user's language) |
| Mature or suggestive themes | **Frequent/Intense** (dating and relationships are the subject of the app) |
| Horror/fear themes | None |
| Medical or treatment information | None |
| Alcohol, tobacco or drug use or references | Infrequent/Mild (first-date suggestions can mention cafés or bars) |
| Simulated gambling / contests / loot boxes | None / No |
| Sexual content or nudity / graphic sexual content | None |
| Health or wellness topics | No |
| Override to a higher rating | If the questionnaire result is below 18+, choose the 18+ (or 17+) override: dating apps are expected to be adults-only |

AI disclosure: in "App Review Information" notes (below) state that the app
generates AI content and that coaches are clearly labelled as AI.

---

## 3. App Privacy (nutrition label)

Matches `ios/Runner/PrivacyInfo.xcprivacy`. App Store Connect › App Privacy.

**Do you or your third-party partners collect data from this app?** Yes.

| Data type | Collected | Linked to the user's identity | Used for tracking | Purposes |
|--|--|--|--|--|
| User Content › Other User Content (chat messages, optional coach memory note, coaching goals and language) | Yes | No | No | App Functionality |
| Purchases › Purchase History (the App Store-signed StoreKit transaction, sent with each message and verified on the server with Apple's certificates; a refund or revocation status is stored as a hash of the transaction ID; with App Store Server Notifications on, the renewal and billing-grace end dates are stored, keyed by a hash, and deleted 35 days after the paid or grace period ends) | Yes | No | No | App Functionality |
| Usage Data › Product Interaction (anonymous counts of coach replies for the fair-use limits, keyed by a one-way salted hash of the transaction ID; daily counts reset daily, monthly counts are kept for the current month) | Yes | No | No | App Functionality |
| Everything else (Contact Info, Health, Financial Info, Location, Sensitive Info, Contacts, Browsing/Search History, Identifiers, other Usage Data, Diagnostics, Audio Data, Photos or Videos, Other) | No | | | |

Resulting label: **Data Not Linked to You**: User Content, Purchases, Usage
Data. No "Data Used to Track You", no "Data Linked to You".

Notes for the owner:
- This is the conservative reading. Messages are processed in real time and
  not stored (privacy policy), which Apple's definition might treat as "not
  collected"; declaring them is still correct and safe.
- Network identifier: a one-way hash of the IP address (or IPv6 network
  block) is used only for rate limiting and abuse protection, and the
  rate-limit entries last about a minute; the IP address itself is not
  stored. The privacy policy discloses it. It is not declared as a collected
  type because it is not retained beyond that short window and is never
  linked to the user. **OWNER:** confirm this reading when you fill in App
  Privacy.
- Audio: speech is recognised on the device; no audio leaves it. Do not
  declare Audio Data.
- If a future version collects gender, age, orientation or city in the
  profile, add Sensitive Info / Coarse Location and update the manifest.

---

## 4. App Review Information

- Sign-in required: **No** (the app has no accounts). Leave the demo account blank.
- Contact: **OWNER** name, phone, email.
- Notes (paste; [SUBMISSION_READY.md](SUBMISSION_READY.md) step 14 links here):

> DateWise AI is an AI dating coach for adults (18+). There is no account or sign-in.
>
> HOW TO TEST
> 1. Launch the app, tap Get started, choose goals and a coaching language, confirm you are 18 or older, and pick a coach.
> 2. Chat requires the auto-renewable subscription "DateWise Premium" (datewise_premium_monthly, 1 month). Tap any coach's chat button or "Talk to <coach>", then Subscribe, and complete the purchase with a Sandbox Apple Account. No DateWise account is needed.
> 3. After purchase, send a message such as "Give me a strong opener". The reply is generated by AI.
> 4. Voice: on Home or in Chat, tap the microphone button, then hold the talk button and speak. Speech recognition runs on the device; the app asks for microphone and speech recognition permission at that moment.
> 5. Restore Purchases is on the paywall and in the You tab. Delete my data is in the You tab.
>
> AI DISCLOSURE
> All four coaches (Ava, Ethan, Sofía, Diego) are AI and are labelled "AI coach" throughout the app. Replies are generated by a large language model (Meta Llama 3.3 70B on Cloudflare Workers AI) through our backend; only the message text, the chosen goals and language, and an optional memory note the user writes are sent, to generate the reply. The app states that advice is not professional advice. Messages are not used to train models.
> On first message the app asks permission to share messages with its AI provider (Cloudflare Workers AI, Meta Llama).
>
> AGE
> Onboarding asks users to confirm they are 18 or older; users who say they are under 18 cannot continue.
>
> FAIR USE
> DateWise Premium has fair-use limits, disclosed on the paywall, in the description and in the Terms of Use: up to 150 coach replies a day and 1,500 a month, at most 12 a minute and 2 at a time. Sandbox purchases (App Review and TestFlight) have a smaller limit of 20 replies a day. A notice appears near the limit.
>
> FIND A TABLE
> Find a table opens Apple Maps; no in-app booking.
>
> OTHER
> No ads, no analytics, no tracking. Encryption: HTTPS only (exempt).

- Attachment: optional screen recording of the purchase flow in sandbox (helps review of subscriptions).

---

## 5. In-app purchase: subscription metadata

Create in App Store Connect › Monetization › Subscriptions (must match
`ios/Runner/DateWise.storekit` and `lib/services/store_service.dart`).

| Field | Value |
|--|--|
| Subscription group reference name | DateWise Premium |
| Group display name (EN / ES) | DateWise Premium / DateWise Premium |
| Product reference name | DateWise Premium Monthly |
| Product ID | `datewise_premium_monthly` (cannot be changed or reused later) |
| Duration | 1 month |
| Price | USD 19.99 (Tier equivalent; let Apple set other storefronts or set manually) |
| Introductory offer / free trial | None |
| Family Sharing | Off |
| Availability | All storefronts where the app is sold |
| Display name (≤35) EN | DateWise Premium Monthly |
| Description (≤55) EN | Chat and voice coaching with all four AI coaches. |
| Display name ES | DateWise Premium Mensual |
| Description ES | Coaching por chat y voz con los cuatro coaches con IA. |
| Review screenshot | Required: a screenshot of the paywall on an iPhone (any supported size, e.g. 1320x2868). Capture it from a TestFlight or simulator build so it shows the real StoreKit price, without the "Review build" note that only the web review build shows. |
| Review notes | "Unlocks chat and voice with the AI coaches. Testable with a Sandbox Apple Account; no app account needed. Fair use: up to 150 coach replies a day and 1,500 a month (Sandbox: 20 a day), at most 12 a minute and 2 at a time." |

The first subscription must be submitted **together with** app version 2.0.0
(select it under "In-App Purchases and Subscriptions" on the version page).

---

## 6. Export compliance

- `ITSAppUsesNonExemptEncryption` = NO is set in `ios/Runner/Info.plist`, so
  App Store Connect will not ask per build.
- If asked: "Does your app use encryption?" **Yes, only standard encryption
  through Apple's operating system (HTTPS/TLS)** → qualifies for the exemption;
  no proprietary or non-standard encryption; no export compliance documents
  needed. (Answer as "None of the algorithms mentioned above" / exempt,
  depending on how the current form words it.)

---

## 7. Screenshots

Generated from the web review build by `tool/appstore_screenshots/generate.sh`
(one command; see `checklist.md`). Files:
`docs/appstore/screenshots/{en,es}/{6.9,6.5,ipad-13}/NN-name.png`

| # | File | EN headline / caption | ES headline / caption |
|--|--|--|--|
| 1 | 01-coaches | Choose your AI dating coach / Four coaches, in English and Spanish | Elige tu coach de citas con IA / Cuatro coaches, en inglés y en español |
| 2 | 02-home | A simple plan for your week / Profile, conversations and first dates | Un plan sencillo para tu semana / Perfil, conversaciones y primeras citas |
| 3 | 03-chat | Know what to say next / Example chat: openers and replies you can adapt | Sabrás qué escribir / Chat de ejemplo: primeros mensajes y respuestas a tu medida |
| 4 | 04-coach | Honest, practical advice / From an AI dating coach, not a person (Welcome screen) | Coaches en español / Sofía y Diego te ayudan en tu idioma (Diego's chat) |
| 5 | 05-privacy | Your data, your controls / Coach memory is off unless you turn it on | Tus datos, tu control / La memoria del coach está apagada salvo que la actives |

Sizes (Apple's "Screenshot specifications", App Store Connect Help,
checked 2026-11-23):

| Set | Pixels | Apple's display class | Required |
|--|--|--|--|
| `6.9` | 1320x2868 | iPhone 6.9" | Yes (or 6.5") |
| `6.5` | 1284x2778 | iPhone 6.5" | Fallback for 6.9" |
| `ipad-13` | 2064x2752 | iPad 13" | Yes: the app runs on iPad (`TARGETED_DEVICE_FAMILY = 1,2`) |

App Store Connect scales these down for smaller iPhones and iPads. The iPad
set shows the app's own iPad layout (1032x1376 points at 2x: wider columns,
taller portraits), not a stretched phone screen.

Honesty: the chats are example conversations produced by the review build's
offline demo coach; the chat caption says "Example chat" / "Chat de
ejemplo". Each coach is shown as a still portrait labelled "AI coach"; no
screenshot shows or implies live video or a real person.
The web review build's "Review build" paywall note never appears in these
five screens.

The screenshots in `docs/appstore/screenshots/` are **final**: they show the
owner-approved portraits (PR #40, merged as `de430f7` on 2026-11-23; same
sizes, RGB without alpha). Regenerate only if the portraits change.
