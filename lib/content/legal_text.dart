/// In-app legal copy for DateWise AI's Privacy Policy and Terms of Use, in
/// English (the governing text) and a Spanish translation. The hosted pages
/// (web/privacy.html, web/terms.html, web/privacy-es.html, web/terms-es.html)
/// are generated from this file by `dart run tool/legal_pages.dart`, so the
/// website matches the app (test/legal_pages_test.dart checks it).
///
/// Format: lines beginning with "# " render as section headings; everything
/// else is body text (see LegalScreen). A bullet's short "Label:" lead-in
/// (see [legalLeadIn]) is shown in bold, in the app and on the web pages.
///
/// The fair-use numbers come from [FairUse] (lib/config/fair_use.dart), the
/// same values the coach backend enforces (backend/wrangler.toml).
library;

import '../config/fair_use.dart';

/// The length of a bullet's bold "Label:" lead-in (up to and including the
/// colon), or 0 when it has none. Lead-ins are short; a colon later in a
/// sentence is not one.
int legalLeadIn(String bullet) {
  final colon = bullet.indexOf(':');
  return colon > 0 && colon <= 64 && colon + 1 < bullet.length ? colon + 1 : 0;
}

String _n(int n, String lang) => FairUse.format(n, lang);

const String kLegalLastUpdated = 'Last updated: November 23, 2026';
const String kLegalLastUpdatedEs = 'Última actualización: 23 de noviembre de 2026';

final String kPrivacyPolicy = '''
$kLegalLastUpdated

DateWise AI ("DateWise AI", "we", "us") provides an AI dating-coaching app with four AI coaches. This policy explains what information the app handles, how it is used, and your choices. DateWise AI is intended only for adults aged 18 and over.

# Information you provide
- No account: DateWise AI has no sign-in and no account. We do not collect your name, email address or password.
- Your coaching preferences: During setup you choose what you want help with, your coaching language and your coach, and you confirm you are 18 or older. These are used only to personalize the coaching.
- Coaching content: The messages you send to your AI coach, typed or spoken.
- Coach memory (optional, off by default): If you turn it on, a short note you write is sent with your messages so your coach can take it into account. You can view, edit or clear it in You › Coach memory.

# Information stored on your device
- Your conversations, preferences, weekly plan, progress counts and Coach memory note are stored locally on your device and are not uploaded to us.

# How we use information
- To provide AI coaching: your messages, your coaching preferences and (only when Coach memory is on) your note are sent to our AI processing provider to generate replies, which are returned to you.
- To operate, secure, and improve the app.
- We do not sell your personal information, do not use your messages to train AI models, and the app contains no advertising, analytics, or tracking.

# Voice
- Voice mode uses your device's built-in speech recognition to turn what you say into text while you hold the talk button (or, with VoiceOver, from when you tap it until you tap it again); only the resulting text is sent to your coach. Replies are read aloud with your device's built-in voices.
- The microphone is used only while you hold the talk button (or, with VoiceOver, from when you tap it until you tap it again). Voice features need your permission and can be turned off in your device settings.

# How your messages are handled
- Messages are transmitted securely to our AI processing provider, processed to generate a reply, and the reply is returned to your device. They are processed transiently and are not stored on our servers. No conversation content is stored on our servers.
- Abuse protection: a one-way hash of your network identifier (your IP address, or the network block of an IPv6 address) is used for rate limiting and to protect the service from abuse. The IP address itself is not stored.

# Subscriptions
- DateWise Premium is purchased and managed through Apple. Apple processes the payment; we do not receive your payment details, your name or your Apple Account details.
- Subscription check: with each message, the app sends Apple's signed proof of your subscription (the StoreKit transaction) to our server. The server verifies it with Apple's certificates.
- Fair-use counts: to apply the fair-use limits in the Terms of Use, the server keeps anonymous counts of coach replies, keyed by a one-way salted hash of the subscription's transaction ID. These counts are not linked to your identity and contain no conversation content.
- Refunds: if Apple reports that a purchase was refunded or revoked, the server stores that status as a hash of the transaction ID, so the transaction is no longer accepted.

# Service providers
- Cloudflare (Workers AI) generates the AI coaching replies; inputs are processed to return a reply and are not used to train models.
- Apple processes subscriptions and provides on-device speech recognition and voices.
- These providers process data only to provide their service to us.

# Data retention and deletion
- On-device data remains until you delete it: You › Delete all conversations, You › Delete my data (erases everything DateWise stored on the device), or uninstalling the app. Deleting your data does not cancel your App Store subscription; to cancel it, go to Settings › [your name] › Subscriptions.
- Messages sent for a reply are not retained on our servers after processing.
- On our server: daily reply counts reset every day (00:00 UTC), monthly counts are kept for the current month only, and rate-limit entries are short-lived (about a minute). A refund or revocation status is kept, as a hash, only so the transaction stays refused.

# Security
All data in transit uses encrypted (HTTPS) connections. No method of transmission or storage is 100% secure, but we take reasonable measures to protect your information.

# International processing
Our providers may process information on servers located in various countries. By using the app you consent to this processing.

# Children
DateWise AI is for users aged 18 and older. We do not knowingly collect data from anyone under 18. If you believe a minor has used the app, contact us.

# Your choices
Your conversations and preferences stay on your device and you can delete them at any time in the app. Our server holds no conversation content and nothing linked to your identity. Depending on where you live, you may have rights to access, correct, or delete your personal information; email support@datewiseai.com.

# Changes to this policy
We may update this policy from time to time. We will revise the "Last updated" date above, and significant changes will be reflected in the app.

# Contact
Questions about privacy or this policy: support@datewiseai.com
Website: https://datewiseai.com
''';

final String kTermsOfService = '''
$kLegalLastUpdated

By using DateWise AI you agree to these terms. DateWise AI is for adults aged 18 and over.

# The service
DateWise AI provides AI-generated dating and profile coaching for informational and entertainment purposes.

# Not professional advice
Suggestions are automated and are not a substitute for professional relationship, psychological, legal, or medical advice. Suggestions are AI opinions, not guarantees; outcomes such as matches, dates, or responses are not promised.

# AI coaches
Ava, Ethan, Sofía and Diego are AI coaches, not people. Their portraits are AI-generated images of fictional coach characters; they do not depict real people.

# Subscription
Coaching chat requires DateWise Premium, an auto-renewable monthly subscription. The price is shown in the app before you buy. Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically each month unless canceled at least 24 hours before the end of the current period. You can manage or cancel it any time in Settings › [your name] › Subscriptions. Coaching chat is available only with this paid subscription.

# Fair use
DateWise Premium includes generous everyday coaching for personal use. To keep the service fast and fair for everyone, each subscription includes up to ${_n(FairUse.dailyReplies, 'en')} coach replies a day and ${_n(FairUse.monthlyReplies, 'en')} a month, at most ${FairUse.perMinute} a minute and ${FairUse.concurrent} at a time. Typed and spoken messages count the same. You will see a notice in the chat when you are close to the daily or monthly limit. When a limit is reached, chat pauses until the next day (00:00 UTC) or the next month.

# Acceptable use
Don't send content you don't have the right to share, and don't use the service for unlawful purposes.

# Your content
You keep ownership of the content you submit. You grant us permission to process it solely to provide the service.

# Availability
The service may change or be unavailable at times and depends on third-party AI providers.

# Changes
We may update these terms; continued use means you accept the changes.

# Contact
Questions about these terms: support@datewiseai.com
''';

/// Spanish translation of [kPrivacyPolicy] (the English text governs).
final String kPrivacyPolicyEs = '''
$kLegalLastUpdatedEs

DateWise AI ("DateWise AI", "nosotros") ofrece una app de coaching de citas con cuatro coaches con inteligencia artificial (IA). Esta política explica qué información maneja la app, cómo se usa y qué opciones tienes. DateWise AI está dirigida únicamente a personas adultas de 18 años o más.

# Información que proporcionas
- Sin cuenta: DateWise AI no tiene inicio de sesión ni cuentas. No recopilamos tu nombre, tu correo electrónico ni contraseñas.
- Tus preferencias de coaching: al configurar la app eliges en qué quieres ayuda, tu idioma y tu coach, y confirmas que tienes 18 años o más. Solo se usan para personalizar el coaching.
- Contenido del coaching: los mensajes que envías a tu coach con IA, escritos o hablados.
- Memoria del coach (opcional, desactivada por defecto): si la activas, una nota breve que escribes se envía con tus mensajes para que tu coach la tenga en cuenta. Puedes verla, editarla o borrarla en Tú › Memoria del coach.

# Información guardada en tu dispositivo
- Tus conversaciones, preferencias, plan semanal, conteos de progreso y la nota de memoria del coach se guardan localmente en tu dispositivo y no se suben a nuestros servidores.

# Cómo usamos la información
- Para darte coaching con IA: tus mensajes, tus preferencias de coaching y (solo si la memoria del coach está activada) tu nota se envían a nuestro proveedor de procesamiento de IA para generar las respuestas, que se te devuelven.
- Para operar, proteger y mejorar la app.
- No vendemos tu información personal, no usamos tus mensajes para entrenar modelos de IA y la app no contiene publicidad, analítica ni rastreo.

# Voz
- El modo de voz usa el reconocimiento de voz integrado de tu dispositivo para convertir en texto lo que dices mientras mantienes presionado el botón para hablar (o, con VoiceOver, desde que lo tocas hasta que lo vuelves a tocar); solo el texto resultante se envía a tu coach. Las respuestas se leen en voz alta con las voces integradas de tu dispositivo.
- El micrófono solo se usa mientras mantienes presionado el botón para hablar (o, con VoiceOver, desde que lo tocas hasta que lo vuelves a tocar). Las funciones de voz necesitan tu permiso y puedes desactivarlas en la configuración de tu dispositivo.

# Cómo se manejan tus mensajes
- Los mensajes se transmiten de forma segura a nuestro proveedor de procesamiento de IA, se procesan para generar una respuesta y la respuesta vuelve a tu dispositivo. Se procesan de forma transitoria y no se guardan en nuestros servidores. No guardamos ningún contenido de tus conversaciones en nuestros servidores.
- Protección contra abusos: un hash unidireccional de tu identificador de red (tu dirección IP o, con IPv6, el bloque de red de la dirección) se usa para limitar la frecuencia de uso y proteger el servicio contra abusos. La dirección IP en sí no se guarda.

# Suscripciones
- DateWise Premium se compra y se administra a través de Apple. Apple procesa el pago; nosotros no recibimos tus datos de pago, tu nombre ni los datos de tu Cuenta de Apple.
- Verificación de la suscripción: con cada mensaje, la app envía a nuestro servidor la prueba firmada por Apple de tu suscripción (la transacción de StoreKit). El servidor la verifica con los certificados de Apple.
- Conteos de uso justo: para aplicar los límites de uso justo de los Términos de uso, el servidor guarda conteos anónimos de respuestas del coach, identificados por un hash unidireccional con sal del ID de transacción de la suscripción. Estos conteos no están vinculados a tu identidad y no contienen nada de tus conversaciones.
- Reembolsos: si Apple informa que una compra se reembolsó o revocó, el servidor guarda ese estado como un hash del ID de transacción, para que la transacción deje de aceptarse.

# Proveedores de servicios
- Cloudflare (Workers AI) genera las respuestas de coaching con IA; los datos se procesan para devolver una respuesta y no se usan para entrenar modelos.
- Apple procesa las suscripciones y ofrece el reconocimiento de voz y las voces del dispositivo.
- Estos proveedores procesan datos solo para prestarnos su servicio.

# Conservación y eliminación de datos
- Los datos del dispositivo se conservan hasta que los eliminas: Tú › Eliminar todas las conversaciones, Tú › Eliminar mis datos (borra todo lo que DateWise guardó en el dispositivo) o desinstalando la app. Eliminar tus datos no cancela tu suscripción del App Store; para cancelarla, ve a Configuración › [tu nombre] › Suscripciones.
- Los mensajes enviados para obtener una respuesta no se conservan en nuestros servidores después de procesarse.
- En nuestro servidor: los conteos diarios de respuestas se reinician cada día (00:00 UTC), los mensuales se conservan solo durante el mes en curso y los registros de límite de frecuencia duran poco (alrededor de un minuto). El estado de un reembolso o una revocación se conserva, como hash, solo para que la transacción siga rechazada.

# Seguridad
Todos los datos en tránsito usan conexiones cifradas (HTTPS). Ningún método de transmisión o almacenamiento es 100 % seguro, pero tomamos medidas razonables para proteger tu información.

# Procesamiento internacional
Nuestros proveedores pueden procesar información en servidores ubicados en distintos países. Al usar la app, aceptas este procesamiento.

# Menores de edad
DateWise AI es para personas de 18 años o más. No recopilamos a sabiendas datos de menores de 18 años. Si crees que un menor usó la app, contáctanos.

# Tus opciones
Tus conversaciones y preferencias permanecen en tu dispositivo y puedes eliminarlas en cualquier momento desde la app. Nuestro servidor no guarda contenido de tus conversaciones ni nada vinculado a tu identidad. Según dónde vivas, puedes tener derecho a acceder, corregir o eliminar tu información personal; escríbenos a support@datewiseai.com.

# Cambios a esta política
Podemos actualizar esta política de vez en cuando. Cambiaremos la fecha de "Última actualización" de arriba, y los cambios importantes se reflejarán en la app.

# Contacto
Preguntas sobre privacidad o sobre esta política: support@datewiseai.com
Sitio web: https://datewiseai.com
''';

/// Spanish translation of [kTermsOfService] (the English text governs).
final String kTermsOfServiceEs = '''
$kLegalLastUpdatedEs

Al usar DateWise AI aceptas estos términos. DateWise AI es para personas adultas de 18 años o más.

# El servicio
DateWise AI ofrece coaching de citas y de perfil generado por inteligencia artificial, con fines informativos y de entretenimiento.

# No es asesoría profesional
Las sugerencias son automáticas y no sustituyen la asesoría profesional en relaciones, psicología, derecho o medicina. Son opiniones de una IA, no garantías; no se prometen resultados como matches, citas o respuestas.

# Coaches con IA
Ava, Ethan, Sofía y Diego son coaches con IA, no personas. Sus retratos son imágenes generadas por IA de personajes ficticios; no representan a personas reales.

# Suscripción
El chat de coaching requiere DateWise Premium, una suscripción mensual de renovación automática. El precio se muestra en la app antes de comprar. El pago se carga a tu Cuenta de Apple al confirmar la compra. La suscripción se renueva automáticamente cada mes, a menos que la canceles al menos 24 horas antes de que termine el período actual. Puedes administrarla o cancelarla en cualquier momento en Configuración › [tu nombre] › Suscripciones. El chat de coaching solo está disponible con esta suscripción de pago.

# Uso justo
DateWise Premium incluye coaching diario generoso para uso personal. Para que el servicio sea rápido y justo para todos, cada suscripción incluye hasta ${_n(FairUse.dailyReplies, 'es')} respuestas del coach al día y ${_n(FairUse.monthlyReplies, 'es')} al mes, con un máximo de ${FairUse.perMinute} por minuto y ${FairUse.concurrent} a la vez. Los mensajes escritos y hablados cuentan igual. Verás un aviso en el chat cuando estés cerca del límite diario o mensual. Al alcanzar un límite, el chat se pausa hasta el día siguiente (00:00 UTC) o el mes siguiente.

# Uso aceptable
No envíes contenido que no tengas derecho a compartir y no uses el servicio con fines ilegales.

# Tu contenido
Conservas la propiedad del contenido que envías. Nos das permiso para procesarlo únicamente para prestarte el servicio.

# Disponibilidad
El servicio puede cambiar o no estar disponible en ocasiones, y depende de proveedores de IA externos.

# Cambios
Podemos actualizar estos términos; si sigues usando el servicio, aceptas los cambios.

# Contacto
Preguntas sobre estos términos: support@datewiseai.com
''';
