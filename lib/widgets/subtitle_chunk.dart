/// Live-subtitle text for the voice conversation: the sentence being spoken,
/// cut at clause boundaries so it fits one or two lines. The full reply is
/// only ever in the message list.
library;

/// A piece of [text] shown as a subtitle: [start] inclusive, [end] exclusive.
class SubtitleSpan {
  const SubtitleSpan(this.start, this.end);
  final int start;
  final int end;
}

final RegExp _sentenceEnd = RegExp(r'[.!?…]+["”’)\]]*(?=\s|$)|\n+');
final RegExp _clauseEnd = RegExp(r'[,;:—–](?=\s)');

/// The spans [text] is shown in, in order: one per sentence, and a long
/// sentence is cut at its commas, colons and dashes (and, failing that, at
/// spaces) into pieces of at most [maxChars] characters. Blank pieces are
/// dropped; the spans never overlap.
List<SubtitleSpan> subtitleSpans(String text, {int maxChars = 96}) {
  final spans = <SubtitleSpan>[];
  void addSentence(int from, int to) {
    // Trim.
    while (from < to && text[from].trim().isEmpty) {
      from++;
    }
    while (to > from && text[to - 1].trim().isEmpty) {
      to--;
    }
    if (to <= from) return;
    if (to - from <= maxChars) {
      spans.add(SubtitleSpan(from, to));
      return;
    }
    // Clause atoms, then words for an atom that is still too long.
    final atoms = <SubtitleSpan>[];
    var a = from;
    for (final m in _clauseEnd.allMatches(text.substring(from, to))) {
      atoms.add(SubtitleSpan(a, from + m.end));
      a = from + m.end;
    }
    atoms.add(SubtitleSpan(a, to));
    final pieces = <SubtitleSpan>[];
    for (final atom in atoms) {
      var s = atom.start;
      while (atom.end - s > maxChars) {
        var cut = text.lastIndexOf(' ', s + maxChars);
        if (cut <= s) cut = s + maxChars;
        pieces.add(SubtitleSpan(s, cut));
        s = cut;
      }
      pieces.add(SubtitleSpan(s, atom.end));
    }
    // Greedy: join neighbouring pieces while they fit.
    var cur = pieces.first;
    for (final p in pieces.skip(1)) {
      if (p.end - cur.start <= maxChars) {
        cur = SubtitleSpan(cur.start, p.end);
      } else {
        _push(spans, text, cur);
        cur = p;
      }
    }
    _push(spans, text, cur);
  }

  var from = 0;
  for (final m in _sentenceEnd.allMatches(text)) {
    addSentence(from, m.end);
    from = m.end;
  }
  addSentence(from, text.length);
  return spans;
}

void _push(List<SubtitleSpan> spans, String text, SubtitleSpan s) {
  var a = s.start, b = s.end;
  while (a < b && text[a].trim().isEmpty) {
    a++;
  }
  while (b > a && text[b - 1].trim().isEmpty) {
    b--;
  }
  if (b > a) spans.add(SubtitleSpan(a, b));
}

/// The subtitle for the character at [charIndex] of [text] (the word being
/// spoken): the span that contains it, or the nearest one before it.
/// Empty for blank text.
String subtitleAt(String text, int charIndex, {int maxChars = 96}) {
  final spans = subtitleSpans(text, maxChars: maxChars);
  if (spans.isEmpty) return '';
  var pick = spans.first;
  for (final s in spans) {
    if (s.start <= charIndex) pick = s;
  }
  return text.substring(pick.start, pick.end).replaceAll(RegExp(r'\s+'), ' ');
}

/// The first subtitle of [text]: what is shown before and between speech.
String firstSubtitle(String text, {int maxChars = 96}) => subtitleAt(text, 0, maxChars: maxChars);
