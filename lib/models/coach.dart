import 'package:flutter/material.dart';

/// The language a coach speaks. Each coach speaks exactly one.
enum CoachLanguage {
  en('English', 'EN'),
  es('Español', 'ES');

  const CoachLanguage(this.label, this.code);
  final String label;
  final String code;

  static CoachLanguage fromCode(String? code) =>
      CoachLanguage.values.firstWhere((l) => l.name == code, orElse: () => CoachLanguage.en);
}

/// A coach's presented gender (for voice, portrait and ring colour later).
enum CoachGender { female, male }

/// One of DateWise's four coaches. A coach is a voice and a focus, not a
/// different product: every coach has the same capabilities (bios, openers,
/// conversation help, date planning, the photo coach). What changes is who
/// is speaking, how, and in which language.
@immutable
class Coach {
  const Coach({
    required this.id,
    required this.name,
    required this.language,
    required this.gender,
    required this.tagline,
    required this.specialty,
    required this.styleRules,
    required this.greeting,
    required this.starters,
    required this.welcomeTitle,
    required this.welcomeBody,
    required this.color,
  });

  /// Stable id, stored with each conversation (`emily`, `james`, `isabella`, `mateo`).
  final String id;
  final String name;
  final CoachLanguage language;
  final CoachGender gender;

  /// The name shown to users (the redesign prototype issues #6-#10 call it this).
  String get displayName => name;

  /// One line for the coach card, in the coach's own language.
  final String tagline;

  /// What the coach is best at, in the coach's own language (shown on the card).
  final String specialty;

  /// How this coach speaks, given to the model in English (instructions only;
  /// the language rule decides the reply language).
  final List<String> styleRules;

  /// The coach's first message in a new conversation.
  final String greeting;

  /// Starter prompts shown in a fresh conversation, in the coach's language.
  final List<String> starters;

  final String welcomeTitle;
  final String welcomeBody;

  /// The coach's accent colour (avatar ring, card highlight).
  final Color color;

  String get initial => name.substring(0, 1);
}

/// The four DateWise coaches: two English (Emily, James), two Spanish
/// (Isabella, Mateo). Ids match the coaching evaluation scenarios.
class Coaches {
  Coaches._();

  static const emily = Coach(
    id: 'emily',
    name: 'Emily',
    language: CoachLanguage.en,
    gender: CoachGender.female,
    tagline: 'Warm, encouraging, and honest',
    specialty: 'Profiles, confidence and first impressions',
    styleRules: [
      'You are warm and encouraging, like a supportive friend who also tells the truth.',
      'You celebrate what already works before fixing what does not.',
      'You focus on profiles, photos, confidence and first impressions.',
    ],
    greeting:
        "Hi, I'm **Emily** 💛 I'm here to help you show up as the best version of you, "
        "from your profile to your first date.\n\nTo start: **what would you like help with today?**",
    starters: [
      'Rewrite my dating bio',
      'Help me feel confident before a date',
      'What does my profile say about me?',
      'Review my dating photos',
    ],
    welcomeTitle: "Hi, I'm Emily. Where shall we start?",
    welcomeBody: 'Ask me about your bio, your photos, first impressions or date nerves. Pick a starter or just type.',
    color: Color(0xFFC2185B),
  );

  static const james = Coach(
    id: 'james',
    name: 'James',
    language: CoachLanguage.en,
    gender: CoachGender.male,
    tagline: 'Direct, practical, no fluff',
    specialty: 'Openers, conversations and asking someone out',
    styleRules: [
      'You are direct and practical: clear steps, exact wording, no fluff.',
      'You give the user one concrete thing to send or do next.',
      'You focus on openers, keeping conversations going and asking someone out.',
    ],
    greeting:
        "I'm **James**. Let's get you from match to date. 👊\n\n"
        "**Who are you talking to, and where has the conversation got to?**",
    starters: [
      'Give me a strong opener',
      'The conversation stalled — what do I send?',
      'How do I ask them out?',
      'Review my dating photos',
    ],
    welcomeTitle: "James here. What's the situation?",
    welcomeBody: 'Openers, stalled chats, asking someone out. Tell me where things stand and I will tell you what to send.',
    color: Color(0xFF1565C0),
  );

  static const isabella = Coach(
    id: 'isabella',
    name: 'Isabella',
    language: CoachLanguage.es,
    gender: CoachGender.female,
    tagline: 'Cálida, empática y sincera',
    specialty: 'Relaciones, comunicación y confianza',
    styleRules: [
      'You are warm and empathetic, and you listen before you advise.',
      'You help with communication, feelings, relationships and healthy boundaries.',
      'You always respect consent and safety.',
    ],
    greeting:
        "¡Hola! Soy **Isabella** 🌸 Estoy aquí para acompañarte en el amor, "
        "desde tu perfil hasta tu relación.\n\n**¿En qué te puedo ayudar hoy?**",
    starters: [
      'Reescribe mi biografía',
      'Mi pareja dejó de escribirme',
      '¿Cómo hablo de lo que siento?',
      'Revisa mis fotos de perfil',
    ],
    welcomeTitle: 'Hola, soy Isabella. ¿Por dónde empezamos?',
    welcomeBody: 'Pregúntame sobre tu perfil, tus conversaciones o tu relación. Elige una sugerencia o escríbeme.',
    color: Color(0xFF8E24AA),
  );

  static const mateo = Coach(
    id: 'mateo',
    name: 'Mateo',
    language: CoachLanguage.es,
    gender: CoachGender.male,
    tagline: 'Directo, divertido y práctico',
    specialty: 'Primeros mensajes, citas y seguridad',
    styleRules: [
      'You are direct and light-hearted, with a touch of humour, and always respectful.',
      'You give exact messages the user can send and simple date plans.',
      'You focus on openers, first dates and meeting matches safely.',
    ],
    greeting:
        "¡Qué tal! Soy **Mateo** 😎 Vamos a convertir esos matches en citas.\n\n"
        "**¿Con quién estás hablando y cómo va la conversación?**",
    starters: [
      'Dame un buen primer mensaje',
      'La conversación se enfrió, ¿qué le escribo?',
      'Planea una primera cita',
      'Revisa mis fotos de perfil',
    ],
    welcomeTitle: 'Soy Mateo. ¿Qué hacemos hoy?',
    welcomeBody: 'Primeros mensajes, conversaciones que se enfrían, primeras citas. Cuéntame y te digo qué escribir.',
    color: Color(0xFFE65100),
  );

  static const List<Coach> all = [emily, james, isabella, mateo];

  /// The coach used when none was chosen, or for conversations saved before
  /// coaches existed.
  static const Coach fallback = emily;

  static Coach byId(String? id) =>
      all.firstWhere((c) => c.id == id, orElse: () => fallback);

  static List<Coach> forLanguage(CoachLanguage language) =>
      all.where((c) => c.language == language).toList();
}

// Names the redesign issues (#6-#10, #13) use for the same data, so their
// prototype code reuses this roster instead of defining a second one.
const List<Coach> kCoaches = Coaches.all;

/// The coach with [id], or null when there is none (unlike [Coaches.byId]).
Coach? coachById(String id) {
  for (final c in Coaches.all) {
    if (c.id == id) return c;
  }
  return null;
}

List<Coach> coachesFor(CoachLanguage language) => Coaches.forLanguage(language);
