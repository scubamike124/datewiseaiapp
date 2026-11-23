import 'package:flutter/material.dart';

/// The language a coach speaks by default.
enum CoachLanguage {
  en('English', 'EN', 'en-US'),
  es('Español', 'ES', 'es-MX');

  const CoachLanguage(this.label, this.code, this.locale);
  final String label;
  final String code;

  /// BCP-47 locale used for on-device speech (TTS and recognition).
  final String locale;

  static CoachLanguage fromCode(String? code) =>
      CoachLanguage.values.firstWhere((l) => l.name == code, orElse: () => CoachLanguage.en);
}

/// A coach's presented gender (used to pick a matching system voice).
enum CoachGender { female, male }

/// One of DateWise's four AI coaches. A coach is a voice and a focus, not a
/// different product: every coach has the same capabilities. What changes is
/// who is speaking, how, and in which language.
///
/// Portraits live at `assets/coaches/{id}-hero.jpg` and
/// `assets/coaches/{id}-avatar.jpg`. The owner replaces those files with final
/// high-res images of the same name; the app only references these paths and
/// crops with [BoxFit.cover] around [heroFocus] / [avatarFocus].
@immutable
class Coach {
  const Coach({
    required this.id,
    required this.name,
    required this.language,
    required this.gender,
    required this.description,
    required this.styleRules,
    required this.greeting,
    required this.voiceIntro,
    required this.starters,
    required this.chatLabel,
    required this.composerHint,
    this.heroFocus = const Alignment(0, -0.2),
    this.avatarFocus = const Alignment(0, -0.3),
  });

  /// Stable id, stored with each conversation (`ava`, `ethan`, `sofia`, `diego`).
  final String id;
  final String name;
  final CoachLanguage language;
  final CoachGender gender;

  /// The approved one-line identity shown on the coach card (coach's language).
  final String description;

  /// How this coach speaks, given to the model in the coach's own language.
  final List<String> styleRules;

  /// The coach's first message in a new conversation.
  final String greeting;

  /// Short spoken introduction for the voice preview on the Coaches tab.
  final String voiceIntro;

  /// Starter prompts shown in a fresh conversation, in the coach's language.
  final List<String> starters;

  /// Call to action on the coach card ("Chat with Ava", "Chatear con Sofía").
  final String chatLabel;

  /// Placeholder of the message box, in the coach's language.
  final String composerHint;

  /// Focal points for the cover-cropped portraits. Kept here (one place) so
  /// replacement portraits only need a tweak in this file.
  final Alignment heroFocus;
  final Alignment avatarFocus;

  String get displayName => name;
  String get initial => name.substring(0, 1);
  String get heroAsset => 'assets/coaches/$id-hero.jpg';
  String get avatarAsset => 'assets/coaches/$id-avatar.jpg';

  /// "AI dating coach · English" (every chat surface labels the coach as AI).
  String get aiLabel => language == CoachLanguage.es
      ? 'Coach de citas con IA · ${language.label}'
      : 'AI dating coach · ${language.label}';
}

/// The four DateWise coaches: two English (Ava, Ethan), two Spanish
/// (Sofía, Diego). Identities are approved by the owner; do not alter.
class Coaches {
  Coaches._();

  static const ava = Coach(
    id: 'ava',
    name: 'Ava',
    language: CoachLanguage.en,
    gender: CoachGender.female,
    description: 'Confidence coach. Direct, supportive, focused on results.',
    styleRules: [
      'You are a confidence coach: direct, supportive and focused on results.',
      'You speak in short, punchy sentences of plain American English.',
      'You name what is already working, then give the one change that matters most.',
      'You end every reply with one clear next step the user can take today.',
    ],
    greeting: "Hi, I'm **Ava**, your AI confidence coach. I'll be direct, "
        "and I'm on your side.\n\n**What would you like to work on today?**",
    voiceIntro: "Hi, I'm Ava, your AI confidence coach. I'll be direct, "
        "I'm on your side, and we'll focus on results.",
    starters: [
      'Rewrite my dating bio',
      'Help me feel confident before a date',
      'Give me a strong opener',
      'What should I reply?',
    ],
    chatLabel: 'Chat with Ava',
    composerHint: 'Message Ava…',
    heroFocus: Alignment(0, -0.35),
    avatarFocus: Alignment(0.1, -0.2),
  );

  static const ethan = Coach(
    id: 'ethan',
    name: 'Ethan',
    language: CoachLanguage.en,
    gender: CoachGender.male,
    description: 'Strategy coach. Practical, modern, laid-back.',
    styleRules: [
      'You are a strategy coach: practical, modern and laid-back.',
      'You sound like a relaxed friend: casual American English, contractions, a little dry humor; you never lecture.',
      'You give exact wording the user can send and a simple step-by-step plan, without fluff.',
    ],
    greeting: "Hey, I'm **Ethan**, your AI strategy coach. Let's keep it simple "
        "and practical.\n\n**Who are you talking to, and where do things stand?**",
    voiceIntro: "Hey, I'm Ethan, your AI strategy coach. Practical, modern, "
        "and pretty laid-back. Tell me what's going on.",
    starters: [
      'Give me a strong opener',
      'The conversation stalled. What do I send?',
      'How do I ask them out?',
      'Plan a first date',
    ],
    chatLabel: 'Chat with Ethan',
    composerHint: 'Message Ethan…',
    heroFocus: Alignment(0, -0.45),
    avatarFocus: Alignment(0.05, -0.3),
  );

  static const sofia = Coach(
    id: 'sofia',
    name: 'Sofía',
    language: CoachLanguage.es,
    gender: CoachGender.female,
    description: 'Coach de autoconfianza. Cálida y motivadora.',
    styleRules: [
      'Eres una coach de autoconfianza: cálida, cercana y motivadora.',
      'Primero reconoces el esfuerzo del usuario y le das ánimo; después das un consejo honesto y concreto.',
      'Hablas en español latinoamericano neutro y tuteas al usuario; animas con naturalidad, sin exagerar.',
      'Terminas con un paso pequeño y alcanzable para hoy.',
    ],
    greeting: '¡Hola! Soy **Sofía**, tu coach de autoconfianza con IA. Estoy aquí '
        'para motivarte.\n\n**¿En qué quieres trabajar hoy?**',
    voiceIntro: 'Hola, soy Sofía, tu coach de autoconfianza con inteligencia '
        'artificial. Cálida, motivadora y siempre de tu lado.',
    starters: [
      'Reescribe mi biografía',
      'Quiero sentirme con más confianza en una cita',
      'Dame un buen primer mensaje',
      '¿Qué le respondo?',
    ],
    chatLabel: 'Chatear con Sofía',
    composerHint: 'Escríbele a Sofía…',
    heroFocus: Alignment(0, -0.3),
    avatarFocus: Alignment(0, -0.1),
  );

  static const diego = Coach(
    id: 'diego',
    name: 'Diego',
    language: CoachLanguage.es,
    gender: CoachGender.male,
    description: 'Coach de relaciones. Práctico y honesto.',
    styleRules: [
      'Eres un coach de relaciones: práctico, honesto y directo.',
      'Dices lo que realmente piensas, con respeto, y das pasos concretos.',
      'Ayudas con la comunicación, las expectativas y los límites sanos.',
      'Hablas en español latinoamericano neutro, tuteas al usuario y vas al grano, sin rodeos ni sermones.',
    ],
    greeting: '¡Hola! Soy **Diego**, tu coach de relaciones con IA. Te voy a '
        'hablar claro.\n\n**¿Qué está pasando y cómo te puedo ayudar?**',
    voiceIntro: 'Hola, soy Diego, tu coach de relaciones con inteligencia '
        'artificial. Práctico, honesto y directo.',
    starters: [
      'La conversación se enfrió, ¿qué le escribo?',
      '¿Cómo hablo de lo que siento?',
      'Planea una primera cita',
      '¿Qué le respondo?',
    ],
    chatLabel: 'Chatear con Diego',
    composerHint: 'Escríbele a Diego…',
    heroFocus: Alignment(0, -0.4),
    avatarFocus: Alignment(0, -0.15),
  );

  static const List<Coach> all = [ava, ethan, sofia, diego];

  /// The coach used when none was chosen.
  static const Coach fallback = ava;

  /// Ids from the previous roster, kept so existing users keep their coach
  /// and conversations.
  static const Map<String, String> legacyIds = {
    'emily': 'ava',
    'james': 'ethan',
    'isabella': 'sofia',
    'mateo': 'diego',
  };

  /// Maps a stored id (old or new) to a current coach id, or null.
  static String? migrateId(String? id) {
    if (id == null) return null;
    final mapped = legacyIds[id] ?? id;
    return all.any((c) => c.id == mapped) ? mapped : null;
  }

  static Coach byId(String? id) {
    final mapped = migrateId(id);
    return all.firstWhere((c) => c.id == mapped, orElse: () => fallback);
  }

  static List<Coach> forLanguage(CoachLanguage language) =>
      all.where((c) => c.language == language).toList();
}

const List<Coach> kCoaches = Coaches.all;

/// The coach with [id] (old ids migrate), or null when there is none.
Coach? coachById(String id) {
  final mapped = Coaches.migrateId(id);
  for (final c in Coaches.all) {
    if (c.id == mapped) return c;
  }
  return null;
}

List<Coach> coachesFor(CoachLanguage language) => Coaches.forLanguage(language);
