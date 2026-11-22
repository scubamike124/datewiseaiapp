import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/chat_message.dart';
import '../models/coach.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';
import 'ai_service.dart';

/// Offline, deterministic coach that lets DateWise AI run end-to-end with no
/// API key. It keys off intent in the user's latest message and answers in
/// the coach's language.
///
/// Replies are streamed word-by-word to mimic the real-time streaming UX.
class MockAIService implements AIService {
  @override
  String get providerLabel => 'DateWise AI (offline demo)';

  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile, // unused: the offline coach infers intent from text
    Coach? coach,
  }) async* {
    final lastUser = history.lastWhere(
      (m) => m.isUser,
      orElse: () => ChatMessage(
        id: 'x',
        role: MessageRole.user,
        text: '',
        createdAt: DateTime(2026),
      ),
    );
    final c = coach ?? Coaches.fallback;
    final reply = c.language == CoachLanguage.es
        ? spanishReply(lastUser.text, c)
        : englishReply(lastUser.text, c);

    // Stream word-by-word with a small delay for a live-typing feel.
    final words = reply.split(' ');
    for (var i = 0; i < words.length; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 22));
      yield i == 0 ? words[i] : ' ${words[i]}';
    }
  }

  /// The offline coach's Spanish answers (Sofía, Diego): the same intents as
  /// the English coach, written in Spanish, so the demo build shows Spanish
  /// coaching end to end without a network.
  @visibleForTesting
  static String spanishReply(String userText, Coach coach) {
    final t = userText.toLowerCase();
    bool has(List<String> words) => words.any(t.contains);
    // Most specific intents first: "fotos de perfil" is about photos, and
    // "se enfrió, ¿qué le escribo?" is a stalled chat, not a first message.
    if (has(['foto'])) {
      return 'Envíame tus fotos y te digo cuáles mantener. La primera debe mostrar **tu cara con buena luz** '
          'y una sonrisa natural.';
    }
    if (has(['enfri', 'no contesta', 'dejó de', 'dejo de', 'ya no me escribe', 'visto'])) {
      return 'Pasa más de lo que crees, y no siempre significa desinterés. Envía **un solo mensaje ligero**, '
          'sin reproches: "¡Oye! Me acordé de ti cuando vi esto, ¿cómo va tu semana?" '
          'Si no responde, deja que la conversación descanse. **¿Cuánto tiempo lleva sin escribir?**';
    }
    if (has(['bio', 'perfil', 'descripción', 'descripcion'])) {
      return 'Me encanta que quieras mejorar tu perfil. Antes de escribirlo, cuéntame tres cosas: '
          '**¿qué te gusta hacer en tu tiempo libre, qué buscas** (algo serio o conocer gente) '
          '**y qué tono prefieres**, divertido o más sincero? Con eso te escribo una biografía que suene a ti.';
    }
    if (has(['primer mensaje', 'abrir', 'opener', 'saludo', 'escribirle', 'qué le escribo', 'que le escribo'])) {
      return 'Un buen primer mensaje habla de **algo concreto de su perfil**. Por ejemplo: '
          '"Vi que te gusta el senderismo, ¿cuál es la mejor ruta que has hecho?" '
          'Es fácil de contestar y muestra que leíste su perfil. **¿Qué aparece en su perfil?**';
    }
    if (has(['cita', 'salir', 'quedar', 'conocer'])) {
      return 'Para una primera cita, algo sencillo y en **un lugar público**: un café o un paseo de una hora. '
          'Avisa a un amigo de dónde estarás y llega por tu cuenta. '
          '**¿Qué les gusta a los dos?** Así te propongo un plan concreto.';
    }
    return 'Cuéntame un poco más: **¿en qué punto estás** (perfil, conversación, primera cita o relación) '
        '**y qué te gustaría conseguir?** Así te doy un consejo concreto.';
  }

  /// The offline coach's English answers (Ava, Ethan), by intent. Like the
  /// Spanish ones, they never mention features the app does not have.
  @visibleForTesting
  static String englishReply(String userText, Coach coach) {
    final t = userText.toLowerCase();
    bool has(List<String> words) => words.any(t.contains);
    if (has(['ghost', 'stalled', 'stopped replying', 'left me on read', 'went quiet'])) {
      return "It happens more than you think, and it doesn't always mean they lost interest. "
          "Send **one light message**, no guilt: \"Hey! Saw this and thought of you. How's your week going?\" "
          "If there's no reply, let it rest and put your energy elsewhere. **How long has it been?**";
    }
    if (has(['bio', 'profile', 'about me'])) {
      return "Let's make your profile sound like you. Tell me three things first: "
          "**what you love doing on a free weekend, what you're looking for** (something serious or meeting people) "
          "**and the tone you want**, playful or sincere. Then I'll write a bio you can paste in tonight.";
    }
    if (has(['opener', 'opening line', 'first message', 'how to start', 'what do i say'])) {
      return "Skip \"hey\". A strong opener mentions **one specific thing from their profile** and is easy to answer. "
          "For example: \"That hiking photo looks unreal. What's the best trail you've done?\" "
          "**What's on their profile?** I'll tailor it.\n"
          "OPTIONS: Playful | \"Be honest: is your dog screening my messages?\" || "
          "Specific | \"That ramen photo is dangerous. Broth first or noodles first?\"";
    }
    if (has(['date', 'ask them out', 'ask her out', 'ask him out'])) {
      return "Keep a first date simple and in **a public place**: coffee or a one-hour walk. "
          "Tell a friend where you'll be and get there on your own. "
          "**What do you both enjoy?** I'll suggest a concrete plan.";
    }
    if (has(['nervous', 'confident', 'anxious'])) {
      return "Nerves just mean you care. Before the date, **plan your first two questions** and take three slow breaths on the way in. "
          "You don't need to be perfect, just present. **What part worries you most?**";
    }
    if (has(['reply', 'respond', 'what should i send', 'what do i send'])) {
      return "Paste their last message and a line of context, and I'll give you **two replies**: one safe, one playful. "
          "**What did they say?**";
    }
    if (has(['practice', 'role', 'play my match'])) {
      return "Let's do it. I'll be your match. **\"Hey! Your profile made me laugh. What's the story behind the karaoke photo?\"** "
          "Your turn: how do you reply?";
    }
    return "Tell me a bit more: **where are you at** (profile, a conversation, a first date or a relationship) "
        "**and what would you like to happen?** Then I'll give you something concrete. I'm ${coach.name}, your AI coach.";
  }
}
