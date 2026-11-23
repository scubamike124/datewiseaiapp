import '../models/coach.dart';

/// Mouth shapes the avatar can show. Each one (except [rest]) is a small
/// photo patch generated offline from the coach's approved portrait
/// (`assets/avatar/<coach>/<asset>.jpg`, see tool/avatar/gen_frames.py).
///
/// Vowels come in two openings: full (stressed syllables) and half
/// (unstressed syllables and function words), so the mouth opens more on the
/// louder syllables even without audio analysis.
enum Viseme {
  /// The approved portrait itself (silence, between sentences).
  rest(null, 0.3),

  /// M, B, P (and Spanish V, and N before them): lips pressed together.
  mbp('mbp', 0.0, closed: true),

  /// A as in "father", "casa": wide open (stressed).
  a('a', 1.0),

  /// A, unstressed: half open.
  a2('a2', 0.55),

  /// E as in "bed", "mesa": open and spread.
  e('e', 0.65),
  e2('e2', 0.4),

  /// I as in "see", "sí": spread, nearly closed.
  i('i', 0.4),
  i2('i2', 0.22),

  /// O as in "go", "oso": rounded and open.
  o('o', 0.8, rounded: true),
  o2('o2', 0.5, rounded: true),

  /// U / W as in "you", "luna": rounded and small.
  u('u', 0.35, rounded: true),
  u2('u2', 0.12, rounded: true, closed: true),

  /// F, V (English): lower lip to the teeth.
  fv('fv', 0.1, closed: true),

  /// L.
  l('l', 0.6),

  /// TH (English), Spanish soft D.
  th('th', 0.45),

  /// T D N S Z K G R Y H...
  cons('cons', 0.4),

  /// SH, CH, J (English), CH (Spanish): lips pushed forward.
  sh('sh', 0.3, rounded: true);

  const Viseme(this.asset, this.openness, {this.rounded = false, this.closed = false});

  /// File name of the patch (without extension), or null for [rest].
  final String? asset;

  /// How open the mouth is (0 closed .. 1 wide).
  final double openness;

  /// Lips rounded / pushed forward.
  final bool rounded;

  /// Lips touching (no teeth visible): never crossfaded with an open shape,
  /// or the teeth would show through the lips.
  final bool closed;

  bool get isVowel => const {a, a2, e, e2, i, i2, o, o2, u, u2}.contains(this);

  /// The half-open variant of a full vowel (itself for anything else).
  Viseme get half => switch (this) {
        a => a2,
        e => e2,
        i => i2,
        o => o2,
        u => u2,
        _ => this,
      };

  /// The full variant of a half vowel (itself for anything else).
  Viseme get full => switch (this) {
        a2 => a,
        e2 => e,
        i2 => i,
        o2 => o,
        u2 => u,
        _ => this,
      };
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
/// these rules decide which mouth shapes fill the word and which syllable is
/// stressed (full opening; the others get the half opening). Spanish spelling
/// is almost phonemic and its stress rules are exact for written words.
/// English uses digraph rules (th, sh, ch, ph, oo, ee...), a silent final "e",
/// first-syllable stress and a list of unstressed function words: an
/// approximation that keeps the mouth plausible, not a phonetic transcription.
abstract class VisemeMapper {
  const VisemeMapper();

  static const VisemeMapper english = _EnglishMapper();
  static const VisemeMapper spanish = _SpanishMapper();

  static VisemeMapper of(CoachLanguage language) => language == CoachLanguage.es ? spanish : english;

  /// Mouth shapes for one word (letters only; punctuation is ignored).
  /// [next] is the following word, for sound changes across words (Spanish
  /// "gran paso": the n closes the lips before the p).
  List<VisemeSegment> word(String word, {String? next});

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

  /// Applies stress: vowels of the [stressed] nucleus (0-based count of
  /// vowel groups) keep the full opening, the others get the half opening.
  /// A null [stressed] makes the whole word unstressed.
  static List<VisemeSegment> stress(List<VisemeSegment> segs, int? stressed) {
    var nucleus = -1;
    var inVowel = false;
    final out = <VisemeSegment>[];
    for (final s in segs) {
      if (s.viseme.isVowel) {
        if (!inVowel) nucleus++;
        inVowel = true;
        final v = nucleus == stressed ? s.viseme.full : s.viseme.half;
        out.add(VisemeSegment(v, s.weight * (nucleus == stressed ? 1.15 : 0.9)));
      } else {
        inVowel = false;
        out.add(s);
      }
    }
    return collapse(out);
  }

  static int nuclei(List<VisemeSegment> segs) {
    var n = 0;
    var inVowel = false;
    for (final s in segs) {
      if (s.viseme.isVowel && !inVowel) n++;
      inVowel = s.viseme.isVowel;
    }
    return n;
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

  static const _unstressed = {
    'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'de', 'del', 'al', 'a', 'y', 'o', 'e', 'u', 'en',
    'con', 'por', 'para', 'que', 'se', 'te', 'me', 'le', 'les', 'lo', 'nos', 'tu', 'mi', 'su', 'sus', 'tus', 'mis',
    'es', 'si', 'ni', 'sin',
  };

  /// Index of the stressed vowel group: the written accent, else the
  /// second-last group for words ending in a vowel, n or s, else the last.
  static int? stressIndex(String raw) {
    final lower = raw.toLowerCase().replaceAll(RegExp('[^a-záéíóúüñ]'), '');
    if (_unstressed.contains(lower)) return null;
    var groups = 0;
    var inVowel = false;
    int? accented;
    for (var k = 0; k < lower.length; k++) {
      final ch = lower[k];
      final vowel = 'aeiouáéíóúü'.contains(ch);
      // Silent u in que/qui/gue/gui is not a vowel group of its own.
      final silentU = ch == 'u' && k > 0 && 'qg'.contains(lower[k - 1]) && k + 1 < lower.length && 'eiéí'.contains(lower[k + 1]);
      if (vowel && !silentU) {
        if (!inVowel) groups++;
        inVowel = true;
        if ('áéíóú'.contains(ch)) accented = groups - 1;
      } else {
        inVowel = false;
      }
    }
    if (groups == 0) return null;
    if (accented != null) return accented;
    final last = lower[lower.length - 1];
    return ('aeiouns'.contains(last) && groups > 1) ? groups - 2 : groups - 1;
  }

  @override
  List<VisemeSegment> word(String raw, {String? next}) {
    final w = _fold(raw).replaceAll(RegExp('[^a-zñ]'), '');
    final nextFirst = next == null ? '' : _fold(next).replaceAll(RegExp('[^a-zñ]'), '');
    final out = <VisemeSegment>[];
    var i = 0;
    String at(int k) => k < w.length ? w[k] : (nextFirst.isNotEmpty ? nextFirst[0] : '');
    while (i < w.length) {
      final ch = w[i];
      final next1 = at(i + 1);
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
          if ((prev == 'q' || prev == 'g') && (next1 == 'e' || next1 == 'i') && i + 1 < w.length) break;
          out.add(const VisemeSegment(Viseme.u, _v));
        case 'y':
          // "y" alone or word-final is the vowel i; otherwise a consonant.
          out.add(i + 1 >= w.length || w.length == 1 ? const VisemeSegment(Viseme.i, _v) : const VisemeSegment(Viseme.cons, _c));
        case 'm' || 'b' || 'p' || 'v':
          // In Spanish, b and v are the same sound: lips together.
          out.add(const VisemeSegment(Viseme.mbp, _c));
        case 'n':
          // n before b, v, p, m (also across words: "gran paso", "envía",
          // "un beso") is pronounced m: lips together.
          out.add(VisemeSegment('bvpm'.contains(next1) && next1.isNotEmpty ? Viseme.mbp : Viseme.cons, _c));
        case 'f':
          out.add(const VisemeSegment(Viseme.fv, _c));
        case 'l':
          if (next1 == 'l' && i + 1 < w.length) {
            // "ll" sounds like "y".
            out.add(const VisemeSegment(Viseme.cons, _c));
            i++;
          } else {
            out.add(const VisemeSegment(Viseme.l, _c));
          }
        case 'd':
          // Soft d between vowels or at the end ("nada", "verdad").
          final prev = i > 0 ? w[i - 1] : '';
          final soft = i + 1 >= w.length || ('aeiou'.contains(prev) && prev.isNotEmpty);
          out.add(VisemeSegment(soft ? Viseme.th : Viseme.cons, _c));
        case 'h':
          // Silent, except in "ch".
          break;
        case 'w':
          out.add(const VisemeSegment(Viseme.u, _c));
        case 'c':
          if (next1 == 'h' && i + 1 < w.length) {
            i++;
            out.add(const VisemeSegment(Viseme.sh, _c));
          } else {
            out.add(const VisemeSegment(Viseme.cons, _c));
          }
        case 'q':
          out.add(const VisemeSegment(Viseme.cons, _c));
        case 'r':
          if (next1 == 'r' && i + 1 < w.length) i++;
          out.add(const VisemeSegment(Viseme.cons, _c));
        default:
          // ñ s z t k g j x (Mexican Spanish: z and soft c are "s").
          out.add(const VisemeSegment(Viseme.cons, _c));
      }
      i++;
    }
    return VisemeMapper.stress(VisemeMapper.collapse(out), stressIndex(raw));
  }
}

class _EnglishMapper extends VisemeMapper {
  const _EnglishMapper();

  // Longest spellings first.
  static const _rules = <String, List<Viseme>>{
    'tion': [Viseme.sh, Viseme.e, Viseme.cons],
    'sion': [Viseme.sh, Viseme.e, Viseme.cons],
    'ough': [Viseme.o],
    'eigh': [Viseme.e, Viseme.i],
    'igh': [Viseme.a, Viseme.i],
    'ing': [Viseme.i, Viseme.cons],
    'th': [Viseme.th],
    'sh': [Viseme.sh],
    'ch': [Viseme.sh],
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
    'j': Viseme.sh,
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
    'she': [Viseme.sh, Viseme.i],
  };

  // Usually unstressed in running speech.
  static const _function = {
    'a', 'an', 'the', 'to', 'of', 'and', 'or', 'in', 'on', 'at', 'for', 'with', 'from', 'by', 'as', 'is', 'are',
    'was', 'be', 'it', 'its', "it's", 'i', "i'm", 'you', 'your', 'we', 'he', 'she', 'they', 'them', 'his', 'her',
    'my', 'me', 'our', 'that', 'than', 'then', 'but', 'if', 'so', 'do', 'can', 'will', 'just', 'not',
  };

  @override
  List<VisemeSegment> word(String raw, {String? next}) {
    final lower = raw.toLowerCase().replaceAll('’', "'");
    final key = lower.replaceAll(RegExp(r"[^a-z']"), '');
    final unstressed = _function.contains(key);
    final known = _words[key];
    List<VisemeSegment> segs;
    if (known != null) {
      segs = VisemeMapper.collapse([for (final v in known) VisemeSegment(v, v.isVowel ? _v : _c)]);
    } else {
      segs = _spell(lower);
    }
    // Content words: the first syllable carries the stress (most English
    // words); words ending in -tion/-sion stress the syllable before it.
    int? stressed = unstressed ? null : 0;
    if (!unstressed && RegExp(r'[ts]ion$').hasMatch(key)) {
      final n = VisemeMapper.nuclei(segs);
      stressed = n >= 2 ? n - 2 : 0;
    }
    return VisemeMapper.stress(segs, stressed);
  }

  List<VisemeSegment> _spell(String lower) {
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
