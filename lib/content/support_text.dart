/// Customer support page text (the App Store Support URL), in English and
/// Spanish. Same format as lib/content/legal_text.dart: "# " headings, "- "
/// bullets with a bold "Label:" lead-in. The hosted pages web/support.html and
/// web/support-es.html are generated from it by `dart run tool/legal_pages.dart`
/// (test/legal_pages_test.dart checks they are up to date).
library;

const String kSupportLastUpdated = 'Last updated: November 24, 2026';
const String kSupportLastUpdatedEs = 'Última actualización: 24 de noviembre de 2026';

const String kSupportPage = '''
$kSupportLastUpdated

Need help with DateWise AI? Email us at support@datewiseai.com. A person reads every message and replies by email. Please tell us your iPhone or iPad model, your iOS version and what happened; never send passwords or payment details.

# Contact us
- Email: support@datewiseai.com
- In the app: You › Support opens a pre-addressed email.
- Privacy questions and data requests: support@datewiseai.com (see the Privacy Policy below).

# Subscription and billing
- Price: DateWise Premium is one auto-renewable monthly subscription. The price for your country is shown in the app before you buy.
- Cancel or manage: on your iPhone or iPad, go to Settings › [your name] › Subscriptions › DateWise AI, or in the app You › Manage subscription. Cancel at least 24 hours before the end of the current period to avoid the next charge.
- Restore purchases: on a new device or after reinstalling, open You › Restore purchases while signed in with the same Apple Account.
- Refunds: Apple handles all payments and refunds. Request one at https://reportaproblem.apple.com. We cannot see or change your payment details.

# Chat and voice
- Coach is not replying: check your internet connection and that DateWise Premium is active (You › Restore purchases). If it still fails, email us with the time it happened.
- AI permission: before your first message, the app asks whether you agree to share your messages with our AI provider. If you tapped Not now, send a message again and tap Agree.
- Voice mode: hold the talk button to speak. If nothing happens, allow Microphone and Speech Recognition for DateWise AI in Settings › Privacy & Security.

# Your data
- Delete conversations: You › Delete all conversations.
- Delete everything and withdraw AI permission: You › Delete my data erases everything DateWise stored on your device, including your permission to share messages with our AI provider. It does not cancel your subscription.
- DateWise AI has no account and stores no conversation content on our servers. Details: https://datewise-legal.lovable.app/privacy-policy

# Legal
- Privacy Policy: https://datewise-legal.lovable.app/privacy-policy
- Terms of Use: https://datewise-legal.lovable.app/terms-of-service
- DateWise AI is for adults aged 18 and over. The coaches are AI, not people, and their suggestions are not professional advice.
''';

const String kSupportPageEs = '''
$kSupportLastUpdatedEs

¿Necesitas ayuda con DateWise AI? Escríbenos a support@datewiseai.com. Una persona lee cada mensaje y responde por correo. Indícanos el modelo de tu iPhone o iPad, tu versión de iOS y qué ocurrió; nunca envíes contraseñas ni datos de pago.

# Contacto
- Correo: support@datewiseai.com
- En la app: Tú › Soporte abre un correo ya dirigido a nosotros.
- Preguntas de privacidad y solicitudes sobre tus datos: support@datewiseai.com (consulta la Política de privacidad más abajo).

# Suscripción y facturación
- Precio: DateWise Premium es una única suscripción mensual de renovación automática. El precio para tu país se muestra en la app antes de comprar.
- Cancelar o administrar: en tu iPhone o iPad, ve a Configuración › [tu nombre] › Suscripciones › DateWise AI, o en la app Tú › Administrar suscripción. Cancela al menos 24 horas antes del final del período actual para evitar el siguiente cargo.
- Restaurar compras: en un dispositivo nuevo o después de reinstalar, abre Tú › Restaurar compras con la misma Cuenta de Apple.
- Reembolsos: Apple gestiona todos los pagos y reembolsos. Solicítalo en https://reportaproblem.apple.com. No podemos ver ni cambiar tus datos de pago.

# Chat y voz
- El coach no responde: revisa tu conexión a internet y que DateWise Premium esté activa (Tú › Restaurar compras). Si sigue fallando, escríbenos indicando la hora en que ocurrió.
- Permiso de IA: antes de tu primer mensaje, la app te pregunta si aceptas compartir tus mensajes con nuestro proveedor de IA. Si tocaste Ahora no, envía un mensaje de nuevo y toca Aceptar.
- Modo de voz: mantén presionado el botón para hablar. Si no pasa nada, permite Micrófono y Reconocimiento de voz para DateWise AI en Configuración › Privacidad y seguridad.

# Tus datos
- Eliminar conversaciones: Tú › Eliminar todas las conversaciones.
- Eliminar todo y retirar el permiso de IA: Tú › Eliminar mis datos borra todo lo que DateWise guardó en tu dispositivo, incluido tu permiso para compartir mensajes con nuestro proveedor de IA. No cancela tu suscripción.
- DateWise AI no tiene cuentas y no guarda contenido de tus conversaciones en nuestros servidores. Detalles: https://datewise-legal.lovable.app/privacy-es.html

# Legal
- Política de privacidad: https://datewise-legal.lovable.app/privacy-es.html
- Términos de uso: https://datewise-legal.lovable.app/terms-es.html
- DateWise AI es para personas de 18 años o más. Los coaches son IA, no personas, y sus sugerencias no son asesoramiento profesional.
''';
