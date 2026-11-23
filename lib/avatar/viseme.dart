import '../models/coach.dart';

/// Mouth shapes the avatar can show. Each one (except [rest]) is a small
/// photo patch generated offline from the coach's approved portrait
/// (`assets/avatar/<coach>/<asset>.jpg`, see tool/avatar/gen_frames.py).
enum Viseme {
  /// The approved portrait itself (silence, between sentences).
  rest(null, 0),

  /// M, B, P (and Spanish V): lips pressed together.
  mbp('mbp', 0.05),

  /// A as in "father", "casa": wide open.
  a('a', 1.0),

  /// E as in "bed", "mesa": open and spread.
  e('e', 0.65),

  /// I as in "see", "sí": spread, nearly closed.
  i('i', 0.4),

  /// O as in "go", "oso": rounded and open.
  o('o', 0.8),

  /// U / W as in "you", "luna": rounded and small.
  u('u', 0.35),

  /// F, V (English): lower lip to the teeth.
  fv('fv', 0.15),

  /// L.
  l('l', 0.6),

  /// TH (English), Spanish soft D and Castilian Z.
  th('th', 0.45),

  /// Other consonants: T D N S Z K G R CH J SH Y H...
  cons('cons', 0.4);

  const Viseme(this.asset, this.openness);

  /// File name of the patch (without extension), or null for [rest].
  final String? asset;

  /// How open the mouth is (0 closed .. 1 wide). Used by tests and the demo
  /// renderer's sanity checks, and to cap jaw motion when blending.
  final double openness;

  bool get isVowel => this == a || this == e || this == i || this == o || this == u;
}

/// One mouth shape inside a word, with its relative duration.
class VisemeSegment {
  const VisemeSegment(this.viseme, this.weight);
  final Viseme viseme;

  /// Relative length (a vowel lasts about twice a consonant).
  final double weight;

  @override
  String toString() => '${viseme.name}:$weight';
}

/// Spelling-to-mouth-shape rules for English and Spanish.
///
/// iOS reports when each word starts (AVSpeechSynthesizer word ranges);
/// these rules decide which mouth shapes fill the word. Spanish spelling is
/// almost phonemic, so its rules are close to exact. English uses digraph
/// rules (th, sh, ch, ph, oo, ee...), a silent final "e" and collapsing of
/// repeated shapes; it is an approximation that keeps the mouth plausible,
/// not a phonetic transcription.
abstract class VisemeMapper {
  const VisemeMapper();

  static const VisemeMapper english = _EnglishMapper();
  static const VisemeMapper spanish = _SpanishMapper();

  static VisemeMapper of(CoachLanguage language) => language == CoachLanguage.es ? spanish : english;

  /// Mouth shapes for one word (letters only; punctuation is ignored).
  List<VisemeSegment> word(String word);

  static const double vowelWeight = 1.7;
  static const double consonantWeight = 1.0;

  /// Merges consecutive equal shapes (their weights add up), so the mouth
  /// does not flicker on double letters.
  static List<VisemeSegment> collapse(List<VisemeSegment> s) {
    final out = <VisemeSegment>[];
    for (final seg in s) {
      if (out.isNotEmpty && out.last.viseme == seg.viseme) {
        out[out.length - 1] = VisemeSegment(seg.viseme, out.last.weight + seg.weight);
      } else {
        out.add(seg);
      }
    }
    return out;
  }
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u');

const _v = VisemeMapper.vowelWeight;
const _c = VisemeMapper.consonantWeight;

class _SpanishMapper extends VisemeMapper {
  const _SpanishMapper();

  @override
  List<VisemeSegment> word(String raw) {
    final w = _fold(raw).replaceAll(RegExp('[^a-zñ]'), '');
    final out = <VisemeSegment>[];
    var i = 0;
    String at(int k) => k < w.length ? w[k] : '';
    while (i < w.length) {
      final ch = w[i];
      final next = at(i + 1);
      switch (ch) {
        case 'a':
          out.add(const VisemeSegment(Viseme.a, _v));
        case 'e':
          out.add(const VisemeSegment(Viseme.e, _v));
        case 'i':
          out.add(const VisemeSegment(Viseme.i, _v));
        case 'o':
          out.add(const VisemeSegment(Viseme.o, _v));
        case 'u':
          // Silent in "que/qui/gue/gui".
          final prev = i > 0 ? w[i - 1] : '';
          if ((prev == 'q' || prev == 'g') && (next == 'e' || next == 'i')) break;
          out.add(const VisemeSegment(Viseme.u, _v));
        case 'y':
          // "y" alone or word-final is the vowel i; otherwise a consonant.
          out.add(next == '' || w.length == 1 ? const VisemeSegment(Viseme.i, _v) : const VisemeSegment(Viseme.cons, _c));
        case 'm' || 'b' || 'p' || 'v':
          // In Spanish, b and v are the same sound: lips together.
          out.add(const VisemeSegment(Viseme.mbp, _c));
        case 'f':
          out.add(const VisemeSegment(Viseme.fv, _c));
        case 'l':
          if (next == 'l') {
            // "ll" sounds like "y".
            out.add(const VisemeSegment(Viseme.cons, _c));
            i++;
          } else {
            out.add(const VisemeSegment(Viseme.l, _c));
          }
        case 'd':
          // Soft d between vowels or at the end ("nada", "verdad").
          final prev = i > 0 ? w[i - 1] : '';
          final soft = next == '' || ('aeiou'.contains(prev) && prev.isNotEmpty);
          out.add(VisemeSegment(soft ? Viseme.th : Viseme.cons, _c));
        case 'h':
          // Silent, except in "ch".
          break;
        case 'w':
          out.add(const VisemeSegment(Viseme.u, _c));
        case 'c':
          if (next == 'h') i++;
          out.add(const VisemeSegment(Viseme.cons, _c));
        case 'q':
          out.add(const VisemeSegment(Viseme.cons, _c));
        case 'r':
          if (next == 'r') i++;
          out.add(const VisemeSegment(Viseme.cons, _c));
        default:
          // n ñ s z t k g j x (Mexican Spanish: z and soft c are "s").
          out.add(const VisemeSegment(Viseme.cons, _c));
      }
      i++;
    }
    return VisemeMapper.collapse(out);
  }
}

class _EnglishMapper extends VisemeMapper {
  const _EnglishMapper();

  // Longest spellings first.
  static const _rules = <String, List<Viseme>>{
    'tion': [Viseme.cons, Viseme.e, Viseme.cons],
    'ough': [Viseme.o],
    'igh': [Viseme.a, Viseme.i],
    'eigh': [Viseme.e, Viseme.i],
    'ing': [Viseme.i, Viseme.cons],
    'th': [Viseme.th],
    'sh': [Viseme.cons],
    'ch': [Viseme.cons],
    'ph': [Viseme.fv],
    'wh': [Viseme.u],
    'qu': [Viseme.cons, Viseme.u],
    'ck': [Viseme.cons],
    'ng': [Viseme.cons],
    'gh': [],
    'kn': [Viseme.cons],
    'wr': [Viseme.cons],
    'oo': [Viseme.u],
    'ee': [Viseme.i],
    'ea': [Viseme.i],
    'ie': [Viseme.i],
    'ey': [Viseme.i],
    'ai': [Viseme.e, Viseme.i],
    'ay': [Viseme.e, Viseme.i],
    'oa': [Viseme.o],
    'ow': [Viseme.a, Viseme.u],
    'ou': [Viseme.a, Viseme.u],
    'oi': [Viseme.o, Viseme.i],
    'oy': [Viseme.o, Viseme.i],
    'au': [Viseme.o],
    'aw': [Viseme.o],
    'ew': [Viseme.u],
    'ue': [Viseme.u],
    'ui': [Viseme.u],
    'er': [Viseme.e, Viseme.cons],
    'ir': [Viseme.e, Viseme.cons],
    'ur': [Viseme.e, Viseme.cons],
    'or': [Viseme.o, Viseme.cons],
    'ar': [Viseme.a, Viseme.cons],
  };

  static const _single = <String, Viseme>{
    'a': Viseme.a,
    'e': Viseme.e,
    'i': Viseme.i,
    'o': Viseme.o,
    'u': Viseme.u,
    'y': Viseme.i,
    'm': Viseme.mbp,
    'b': Viseme.mbp,
    'p': Viseme.mbp,
    'f': Viseme.fv,
    'v': Viseme.fv,
    'l': Viseme.l,
    'w': Viseme.u,
  };

  // A few very common words whose spelling misleads the rules.
  static const _words = <String, List<Viseme>>{
    'i': [Viseme.a, Viseme.i],
    "i'm": [Viseme.a, Viseme.i, Viseme.mbp],
    'you': [Viseme.i, Viseme.u],
    'your': [Viseme.i, Viseme.o, Viseme.cons],
    'one': [Viseme.u, Viseme.a, Viseme.cons],
    'the': [Viseme.th, Viseme.e],
    'to': [Viseme.cons, Viseme.u],
    'do': [Viseme.cons, Viseme.u],
    'what': [Viseme.u, Viseme.a, Viseme.cons],
    'are': [Viseme.a, Viseme.cons],
    'have': [Viseme.cons, Viseme.a, Viseme.fv],
    'love': [Viseme.l, Viseme.a, Viseme.fv],
    'date': [Viseme.cons, Viseme.e, Viseme.i, Viseme.cons],
    'be': [Viseme.mbp, Viseme.i],
    'we': [Viseme.u, Viseme.i],
    'me': [Viseme.mbp, Viseme.i],
    'he': [Viseme.cons, Viseme.i],
    'she': [Viseme.cons, Viseme.i],
  };

  @override
  List<VisemeSegment> word(String raw) {
    final lower = raw.toLowerCase().replaceAll('’', "'");
    final known = _words[lower.replaceAll(RegExp(r"[^a-z']"), '')];
    if (known != null) return VisemeMapper.collapse([for (final v in known) VisemeSegment(v, v.isVowel ? _v : _c)]);
    var w = lower.replaceAll(RegExp('[^a-z]'), '');
    // Silent final "e" ("make", "date"), but not in "be", "the", "he".
    if (w.length > 3 && w.endsWith('e') && !w.endsWith('ee') && !'aeiou'.contains(w[w.length - 2])) {
      w = w.substring(0, w.length - 1);
    }
    final out = <VisemeSegment>[];
    var i = 0;
    outer:
    while (i < w.length) {
      for (final len in const [4, 3, 2]) {
        if (i + len <= w.length) {
          final rule = _rules[w.substring(i, i + len)];
          if (rule != null) {
            for (final v in rule) {
              out.add(VisemeSegment(v, v.isVowel ? _v : _c));
            }
            i += len;
            continue outer;
          }
        }
      }
      final v = _single[w[i]] ?? Viseme.cons;
      // "y" at the start of a word is a consonant ("yes").
      final seg = (w[i] == 'y' && i == 0) ? Viseme.cons : v;
      out.add(VisemeSegment(seg, seg.isVowel ? _v : _c));
      i++;
    }
    return VisemeMapper.collapse(out);
  }
}
