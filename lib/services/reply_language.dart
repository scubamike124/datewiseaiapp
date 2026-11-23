import '../models/chat_message.dart';
import '../models/coach.dart';

/// Tells English from Spanish with a small heuristic, for the two places
/// where the voice must follow the language actually used: reading a reply
/// aloud (coaches answer in the user's language) and choosing the mic
/// language. No network, no model, no dependency.
///
/// Spanish markers (¿ ¡ ñ and accented vowels) and common words of each
/// language are counted; the higher score wins, and a tie (short or neutral
/// text such as "ok" or "jaja") returns the fallback.
class ReplyLanguage {
  ReplyLanguage._();

  static final _word = RegExp(r"[a-záéíóúüñ']+");
  static final _strongEs = RegExp(r'[¿¡ñ]');
  static final _accentEs = RegExp(r'[áéíóúü]');

  /// Frequent words that are clearly one language. Words used in both
  /// ("a", "no", "me", "he", "solo") are left out on purpose.
  static const _es = {
    'que', 'qué', 'de', 'del', 'la', 'el', 'los', 'las', 'y', 'es', 'en', 'un', 'una', 'por', 'para',
    'con', 'pero', 'como', 'cómo', 'más', 'muy', 'tu', 'tú', 'yo', 'mi', 'mis', 'su', 'sus', 'se',
    'lo', 'le', 'al', 'esta', 'está', 'este', 'eso', 'esto', 'hola', 'gracias', 'quiero', 'puedo',
    'puedes', 'tengo', 'estoy', 'soy', 'cita', 'mensaje', 'también', 'porque', 'cuando', 'sí', 'ella',
    'él', 'nos', 'hacer', 'bien', 'ayuda', 'ayúdame', 'te', 'dónde', 'cuál', 'mucho', 'algo',
  };
  static const _en = {
    'the', 'and', 'you', "you're", 'your', 'to', 'is', 'are', 'of', 'it', "it's", 'that', 'in', 'for',
    'with', 'my', 'i', "i'm", "don't", 'what', 'how', 'hi', 'hello', 'hey', 'thanks', 'want', 'can',
    'do', 'be', 'this', 'on', 'not', 'have', 'help', 'date', 'she', 'we', 'just', 'about', 'but',
    'if', 'would', 'should', 'her', 'him', 'they', 'was', 'will', 'there', 'when', 'really',
  };

  /// The language of [text], or [fallback] when the text gives no clear sign.
  static CoachLanguage detect(String text, {required CoachLanguage fallback}) {
    final t = text.toLowerCase().replaceAll('\u2019', "'");
    var es = 3 * _strongEs.allMatches(t).length + _accentEs.allMatches(t).length;
    var en = 0;
    for (final m in _word.allMatches(t)) {
      final w = m[0]!;
      if (_es.contains(w)) es++;
      if (_en.contains(w)) en++;
    }
    if (es > en) return CoachLanguage.es;
    if (en > es) return CoachLanguage.en;
    return fallback;
  }

  /// The mic language for a chat with [coach]: the coach's language, unless
  /// the user's last message in [messages] was in the other language.
  static CoachLanguage forMic(Coach coach, Iterable<ChatMessage> messages) {
    final lastUser = messages.where((m) => m.isUser && m.text.trim().isNotEmpty).lastOrNull;
    if (lastUser == null) return coach.language;
    return detect(lastUser.text, fallback: coach.language);
  }
}
