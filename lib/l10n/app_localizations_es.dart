// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'DateWise AI';

  @override
  String get back => 'Atrás';

  @override
  String get continueAction => 'Continuar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Eliminar';

  @override
  String get clear => 'Borrar';

  @override
  String get retry => 'Reintentar';

  @override
  String get languageNameEn => 'Inglés';

  @override
  String get languageNameEs => 'Español';

  @override
  String get coachesForEn => 'Coaches: Ava y Ethan';

  @override
  String get coachesForEs => 'Coaches: Sofía y Diego';

  @override
  String coachChip(String name, String language) {
    return '$name · coach con IA · $language';
  }

  @override
  String coachAiLabel(String language) {
    return 'Coach de citas con IA · $language';
  }

  @override
  String coachPortrait(String name) {
    return 'Retrato de $name, coach con IA';
  }

  @override
  String coachPortraitStill(String name) {
    return '$name, coach con IA (retrato fijo)';
  }

  @override
  String get coachDescAva =>
      'Coach de autoconfianza. Directa, comprensiva y enfocada en resultados.';

  @override
  String get coachDescEthan =>
      'Coach de estrategia. Práctico, moderno y relajado.';

  @override
  String get coachDescSofia => 'Coach de autoconfianza. Cálida y motivadora.';

  @override
  String get coachDescDiego => 'Coach de relaciones. Práctico y honesto.';

  @override
  String chatWith(String name) {
    return 'Chatear con $name';
  }

  @override
  String get yourCoachBadge => 'Tu coach';

  @override
  String get stopPreview => 'Detener vista previa';

  @override
  String hearCoach(String name) {
    return 'Escuchar a $name';
  }

  @override
  String get tabHome => 'Inicio';

  @override
  String get tabCoaches => 'Coaches';

  @override
  String get tabChat => 'Chat';

  @override
  String get tabProgress => 'Progreso';

  @override
  String get tabYou => 'Tú';

  @override
  String tabSemantics(String label) {
    return 'Pestaña $label';
  }

  @override
  String get welcomePortrait => 'Ava, una coach de citas con IA, sonriendo';

  @override
  String get welcomeTitleLead => 'Conoce a tu\ncoach de citas ';

  @override
  String get welcomeTitleAccent => 'con IA.';

  @override
  String get welcomeBody =>
      'Ayuda honesta con tu perfil, tus mensajes y tu primera cita, de un coach que te escucha.';

  @override
  String get getStarted => 'Comenzar';

  @override
  String get valueConversations => 'Mejores conversaciones';

  @override
  String get valueProfile => 'Ayuda con tu perfil';

  @override
  String get valueDates => 'Planes para la primera cita';

  @override
  String get welcomeFootnote =>
      'Coaches con IA · Solo para mayores de 18 años · English · Español';

  @override
  String stepOf(int step, int total) {
    return 'Paso $step de $total';
  }

  @override
  String get goalsTitle => '¿Con qué te gustaría recibir ayuda?';

  @override
  String get goalsSubtitle => 'Elige hasta tres. Serán tu plan de la semana.';

  @override
  String get goalConversations => 'Mejores conversaciones';

  @override
  String get goalProfile => 'Un perfil más atractivo';

  @override
  String get goalDates => 'Primeras citas geniales';

  @override
  String get goalConfidence => 'Más confianza';

  @override
  String get goalRelationship => 'Una relación más sana';

  @override
  String get languageTitle => 'Elige tu idioma';

  @override
  String get languageSubtitle =>
      'La app y tus coaches lo usarán. Puedes cambiarlo cuando quieras en la pestaña Tú.';

  @override
  String get ageTitle => 'DateWise es solo para adultos.';

  @override
  String get ageSubtitle => 'Confirma tu edad para continuar.';

  @override
  String get ageConfirm => 'Tengo 18 años o más';

  @override
  String get ageUnder => 'Tengo menos de 18 años';

  @override
  String get underageTitle => 'Lo sentimos, DateWise es solo para adultos.';

  @override
  String get underageBody =>
      'Necesitas tener 18 años o más para usar DateWise AI.';

  @override
  String get chooseCoachTitle => 'Elige a tu coach de citas';

  @override
  String get chooseCoachSubtitle =>
      'Los cuatro son coaches con IA. Elige un estilo y cámbialo cuando quieras.';

  @override
  String get coachesEyebrow => 'Coaches de citas con IA';

  @override
  String get greetingMorning => 'Buenos días.';

  @override
  String get greetingAfternoon => 'Buenas tardes.';

  @override
  String get greetingEvening => 'Buenas noches.';

  @override
  String homeReady(String name, String gender) {
    String _temp0 = intl.Intl.selectLogic(gender, {
      'female': 'lista',
      'other': 'listo',
    });
    return '$name está $_temp0 cuando tú quieras. Tu coach con IA, a cualquier hora.';
  }

  @override
  String homeResume(String name, String gender, String title) {
    String _temp0 = intl.Intl.selectLogic(gender, {
      'female': 'lista',
      'other': 'listo',
    });
    return '$name está $_temp0 cuando tú quieras. Retoma donde lo dejaste: “$title”';
  }

  @override
  String talkTo(String name) {
    return 'Hablar con $name';
  }

  @override
  String voiceChatWith(String name) {
    return 'Hablar por voz con $name';
  }

  @override
  String get planThisWeek => 'Tu plan de esta semana';

  @override
  String get planDone => 'Hecho';

  @override
  String get planNext => 'Siguiente';

  @override
  String get planNotYet => 'Pendiente';

  @override
  String planItemConversations(String name) {
    return 'Practica un primer mensaje con $name';
  }

  @override
  String planItemProfile(String name) {
    return 'Reescribe tu biografía con $name';
  }

  @override
  String get planItemDates => 'Planea una primera cita';

  @override
  String get planItemConfidence => 'Habla de lo que te genera nervios';

  @override
  String get planItemRelationship => 'Practica decir lo que sientes';

  @override
  String get planPromptConversations =>
      'Ayúdame a practicar un primer mensaje para alguien con quien hice match.';

  @override
  String get planPromptProfile => 'Reescribe mi biografía de citas.';

  @override
  String get planPromptDates => 'Ayúdame a planear una buena primera cita.';

  @override
  String get planPromptConfidence =>
      'Me dan nervios antes de una cita. ¿Me ayudas?';

  @override
  String get planPromptRelationship =>
      'Ayúdame a decirle a mi pareja cómo me siento.';

  @override
  String get quickPractice => 'Practicar una conversación';

  @override
  String get quickPracticePrompt =>
      'Practiquemos una conversación. Tú haces de mi match y yo respondo.';

  @override
  String get quickProfile => 'Mejorar mi perfil';

  @override
  String get quickProfilePrompt => 'Ayúdame a mejorar mi perfil de citas.';

  @override
  String get quickDate => 'Prepararme para una cita';

  @override
  String get quickDatePrompt => 'Ayúdame a prepararme para una cita.';

  @override
  String get quickReply => 'Ayúdame a responder';

  @override
  String get quickReplyPrompt => 'Ayúdame a responder un mensaje.';

  @override
  String get voicePermissionNeeded =>
      'La voz necesita acceso al micrófono y al reconocimiento de voz. Puedes permitirlo en Configuración.';

  @override
  String voiceUnavailableNote(String name) {
    return 'La voz no está disponible en este dispositivo. Puedes escribirle a $name.';
  }

  @override
  String get newConversation => 'Nueva conversación';

  @override
  String pastConversationsWith(String name) {
    return 'Conversaciones anteriores con $name';
  }

  @override
  String get switchCoach => 'Cambiar de coach';

  @override
  String get noSavedConversations => 'Aún no tienes conversaciones guardadas.';

  @override
  String conversationsWith(String name) {
    return 'Conversaciones con $name';
  }

  @override
  String get deleteConversation => 'Eliminar conversación';

  @override
  String get conversationOptions => 'Opciones de la conversación';

  @override
  String voiceSession(String elapsed) {
    return 'Sesión de voz · $elapsed';
  }

  @override
  String get hideCaptions => 'Ocultar subtítulos';

  @override
  String get showCaptions => 'Mostrar subtítulos';

  @override
  String coachTyping(String name) {
    return '$name está escribiendo';
  }

  @override
  String coachSays(String name, String text) {
    return '$name: $text';
  }

  @override
  String youSaid(String text) {
    return 'Tú: $text';
  }

  @override
  String copyReply(String label, String text) {
    return 'Copiar respuesta $label: $text';
  }

  @override
  String get copiedReply => 'Copiado. Pégalo en tu app de citas.';

  @override
  String messageHint(String name) {
    return 'Escríbele a $name…';
  }

  @override
  String get voiceMode => 'Modo de voz';

  @override
  String get send => 'Enviar';

  @override
  String get stopReply => 'Detener respuesta';

  @override
  String get listening => 'Escuchando…';

  @override
  String get typeInstead => 'Escribir en lugar de hablar';

  @override
  String get holdToTalk => 'Mantén presionado para hablar';

  @override
  String get stopReadingAloud => 'Dejar de leer las respuestas en voz alta';

  @override
  String get readAloud => 'Leer las respuestas en voz alta';

  @override
  String holdToTalkFooter(String name, String gender) {
    String _temp0 = intl.Intl.selectLogic(gender, {
      'female': 'una',
      'other': 'un',
    });
    return 'Mantén presionado para hablar · $name es $_temp0 coach con IA';
  }

  @override
  String tapToTalkFooter(String name, String gender) {
    String _temp0 = intl.Intl.selectLogic(gender, {
      'female': 'una',
      'other': 'un',
    });
    return 'Toca para hablar · $name es $_temp0 coach con IA';
  }

  @override
  String get premiumEyebrow => 'DateWise Premium';

  @override
  String lockedTitle(String name) {
    return 'El chat con $name forma parte de DateWise Premium.';
  }

  @override
  String get lockedBody =>
      'Suscríbete para hablar con los cuatro coaches con IA. Tus conversaciones se quedan en este dispositivo.';

  @override
  String get seePremium => 'Ver DateWise Premium';

  @override
  String get chatErrorUnavailable =>
      'No se pudo conectar con tu coach. Revisa tu conexión e inténtalo de nuevo. Tu mensaje está guardado.';

  @override
  String get chatErrorBusy =>
      'Tu coach está recibiendo muchos mensajes en este momento. Inténtalo de nuevo en un momento. Tu mensaje está guardado.';

  @override
  String get chatErrorOffline =>
      'Parece que no tienes conexión. Revisa tu conexión e inténtalo de nuevo. Tu mensaje está guardado.';

  @override
  String get chatErrorServer =>
      'El coaching no está disponible por ahora. Inténtalo de nuevo en unos minutos. Tu mensaje está guardado.';

  @override
  String get chatErrorStopped =>
      'La respuesta se detuvo. Tu mensaje está guardado.';

  @override
  String paywallHeadline(String name) {
    return 'Coaching diario con $name y todo el equipo.';
  }

  @override
  String get benefitCoaches =>
      'Chatea con los cuatro coaches con IA, en inglés y en español';

  @override
  String get benefitVoice =>
      'Práctica por voz: habla y escucha las respuestas en tu dispositivo';

  @override
  String get benefitPlan =>
      'Tu plan semanal y tu progreso, guardados en tu dispositivo';

  @override
  String get monthlyAutoRenews => 'Mensual · renovación automática';

  @override
  String get perMonth => 'al mes';

  @override
  String pricePerMonth(String price) {
    return '$price/mes';
  }

  @override
  String subscribeFor(String price) {
    return 'Suscribirme por $price/mes';
  }

  @override
  String get paywallWebOnly =>
      'Suscríbete desde la app para iPhone. Las compras no están disponibles en la web.';

  @override
  String get purchasePending =>
      'Tu compra está pendiente de aprobación. El chat se desbloquea en cuanto se apruebe.';

  @override
  String get purchaseFailed =>
      'No se pudo completar la compra. Inténtalo de nuevo.';

  @override
  String get purchasesUnavailable =>
      'Las compras no están disponibles en este momento.';

  @override
  String get storeUnavailable =>
      'El App Store no está disponible en este momento.';

  @override
  String get storeUnreachable => 'No se pudo conectar con el App Store.';

  @override
  String get productUnavailable =>
      'DateWise Premium aún no está disponible en la tienda.';

  @override
  String get restoreFailed => 'No se pudieron restaurar las compras.';

  @override
  String get noSubscriptionForAppleId =>
      'No se encontró una suscripción activa a DateWise Premium para esta Cuenta de Apple.';

  @override
  String get reviewBuildNote =>
      'Versión de revisión: las compras son simuladas y no se cobra nada.';

  @override
  String paywallDisclosure(String perMonth, String price) {
    return '$perMonth. El pago se carga a tu Cuenta de Apple al confirmar la compra. La suscripción se renueva automáticamente cada mes por $price, a menos que la canceles al menos 24 horas antes de que termine el período actual. Cancela cuando quieras en Configuración › [tu nombre] › Suscripciones.';
  }

  @override
  String get priceFromAppStore => 'Precio indicado por el App Store';

  @override
  String get subscribe => 'Suscribirme';

  @override
  String paywallFairUse(
    String daily,
    String monthly,
    String perMinute,
    String concurrent,
  ) {
    return 'Uso justo: hasta $daily respuestas del coach al día y $monthly al mes, con un máximo de $perMinute por minuto y $concurrent a la vez. Los mensajes escritos y hablados cuentan igual. Verás un aviso cerca de un límite; al alcanzarlo, el chat se pausa hasta el día siguiente (00:00 UTC) o el mes siguiente.';
  }

  @override
  String get paywallDisclosureNoPrice =>
      'Suscripción mensual al precio indicado por el App Store. El pago se carga a tu Cuenta de Apple al confirmar la compra. La suscripción se renueva automáticamente cada mes a ese precio, a menos que la canceles al menos 24 horas antes de que termine el período actual. Cancela cuando quieras en Configuración › [tu nombre] › Suscripciones.';

  @override
  String get tapToSend => 'Detener y enviar';

  @override
  String get tapToTalkHint =>
      'Toca dos veces para empezar a hablar y otra vez para enviar';

  @override
  String get voiceRecognitionUnavailable =>
      'El reconocimiento de voz no está disponible en este dispositivo por ahora. Puedes escribir tu mensaje.';

  @override
  String get voiceLanguageUnsupported =>
      'La voz no está disponible para este idioma en este dispositivo. Puedes escribir tu mensaje.';

  @override
  String get photoNoLongerAvailable =>
      'Foto de una versión anterior (ya no disponible)';

  @override
  String get restorePurchases => 'Restaurar compras';

  @override
  String get termsOfUse => 'Términos de uso';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get privacyShort => 'Privacidad';

  @override
  String get progressTitle => 'Progreso';

  @override
  String get progressSubtitle =>
      'Calculado en este dispositivo a partir de lo que realmente hiciste.';

  @override
  String statConversations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'conversaciones',
      one: 'conversación',
    );
    return '$_temp0';
  }

  @override
  String statStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días de racha',
      one: 'día de racha',
    );
    return '$_temp0';
  }

  @override
  String statDaysUsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días con un coach',
      one: 'día con un coach',
    );
    return '$_temp0';
  }

  @override
  String statPlanDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pasos del plan completados esta semana',
      one: 'paso del plan completado esta semana',
    );
    return '$_temp0';
  }

  @override
  String noDaysYet(String name) {
    return 'Aún no tienes días de coaching. Envíale un mensaje a $name para empezar tu racha.';
  }

  @override
  String daysTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '1 día',
    );
    return 'En total, hablaste con un coach $_temp0.';
  }

  @override
  String get weekPlanTitle => 'El plan de esta semana';

  @override
  String planCount(int done, int total) {
    return '$done de $total completados';
  }

  @override
  String get progressFootnote =>
      'Marca los pendientes del plan en Inicio. Las marcas se reinician cada lunes.';

  @override
  String get youTitle => 'Tú';

  @override
  String get sectionCoaching => 'Coaching';

  @override
  String get languageRow => 'Idioma';

  @override
  String get yourCoachRow => 'Tu coach';

  @override
  String get sectionMemory => 'Memoria del coach';

  @override
  String get memoryTitle => 'Memoria del coach';

  @override
  String get memoryOn => 'Activada: tu nota se envía con cada mensaje.';

  @override
  String get memoryOff =>
      'Desactivada: no se guarda ninguna nota (al desactivarla se borra) y los coaches solo ven la conversación actual.';

  @override
  String get writeNote => 'Escribe tu nota';

  @override
  String get yourNote => 'Tu nota';

  @override
  String get clearMemory => 'Borrar memoria';

  @override
  String get clearMemoryTitle => '¿Borrar la memoria del coach?';

  @override
  String get clearMemoryBody => 'Tu nota se eliminará de este dispositivo.';

  @override
  String get memoryOffTitle => '¿Desactivar la memoria del coach?';

  @override
  String get memoryOffBody =>
      'Tu nota se eliminará de este dispositivo y los coaches solo verán la conversación actual.';

  @override
  String get memoryTurnOnTitle => '¿Activar la memoria del coach?';

  @override
  String get memoryTurnOnBody =>
      'Tu nota solo se guarda mientras la memoria del coach está activada. Entonces se enviará a tu coach con cada mensaje.';

  @override
  String get memoryTurnOnAction => 'Activar y guardar';

  @override
  String get memoryOffAction => 'Desactivar y borrar';

  @override
  String get memorySheetBody =>
      'Una nota breve que tus coaches ven con cada mensaje mientras la memoria del coach está activada. Escribe solo lo que quieras compartir.';

  @override
  String get memoryHint =>
      'p. ej.: Tengo 31 años, me cuesta abrirme al principio, uso Hinge y busco algo serio.';

  @override
  String get sectionSubscription => 'Suscripción';

  @override
  String get subActive => 'Activa';

  @override
  String get subNone => 'Sin suscripción';

  @override
  String get manageSubscription => 'Administrar suscripción';

  @override
  String get restorePurchasesRow => 'Restaurar compras';

  @override
  String get restoreOk => 'DateWise Premium está activa.';

  @override
  String get restoreNone => 'No se encontró una suscripción activa.';

  @override
  String get sectionData => 'Tus datos';

  @override
  String get deleteAllConversations => 'Eliminar todas las conversaciones';

  @override
  String get deleteAllConversationsTitle =>
      '¿Eliminar todas las conversaciones?';

  @override
  String get deleteAllConversationsBody =>
      'Todas las conversaciones con todos los coaches se eliminarán de este dispositivo.';

  @override
  String get deleteMyData => 'Eliminar mis datos';

  @override
  String get deleteMyDataNote =>
      'No cancela tu suscripción. Cancélala en la configuración de Apple.';

  @override
  String get deleteMyDataTitle => '¿Eliminar todos tus datos?';

  @override
  String get deleteMyDataBody =>
      'Las conversaciones, el plan, el progreso, la memoria del coach y tus preferencias se borrarán de este dispositivo, y la app empezará de nuevo.\n\nTu suscripción la administra Apple y sigue activa: eliminar tus datos no la cancela. Para cancelarla, ve a Configuración › [tu nombre] › Suscripciones.';

  @override
  String get deleteEverything => 'Eliminar todo';

  @override
  String get sectionAbout => 'Acerca de';

  @override
  String get support => 'Soporte';

  @override
  String couldNotOpen(String url) {
    return 'No se pudo abrir $url';
  }

  @override
  String get settingsFootnote =>
      'Tus coaches son IA. Las conversaciones se guardan en este dispositivo.';

  @override
  String appVersion(String version) {
    return 'DateWise AI $version';
  }

  @override
  String get legalTranslationNote =>
      'Esta es una traducción para tu comodidad. Si difiere de la versión en inglés, prevalece la versión en inglés.';

  @override
  String get coachLimitDaily =>
      'Llegaste al límite de coaching de hoy. Se renueva a la medianoche (UTC).';

  @override
  String get coachLimitMonthly =>
      'Llegaste al límite de uso justo de este mes. Se renueva el día 1.';

  @override
  String get coachLimitSlowDown =>
      'Estás enviando mensajes muy rápido. Espera un momento e inténtalo de nuevo.';

  @override
  String get coachLimitBusy =>
      'El coaching está muy ocupado en este momento. Inténtalo más tarde.';

  @override
  String get coachLimitSubscriptionInactive =>
      'Tu suscripción a DateWise Premium no está activa. Renuévala para seguir chateando.';

  @override
  String get coachLimitRevoked =>
      'Esta compra fue reembolsada o revocada, así que el coaching está bloqueado.';

  @override
  String get coachLimitVerify =>
      'No pudimos confirmar tu suscripción. Toca Restaurar compras.';

  @override
  String get coachLimitUpdateApp =>
      'Actualiza DateWise a la última versión para seguir chateando con tu coach.';

  @override
  String get coachUsageNoticeDaily =>
      'Te estás acercando al límite de uso justo de hoy.';

  @override
  String get coachUsageNoticeMonthly =>
      'Te estás acercando al límite de uso justo de este mes.';
}
