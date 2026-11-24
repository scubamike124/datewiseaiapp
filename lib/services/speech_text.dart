import '../models/coach.dart';

/// One piece of a reply that is spoken as its own utterance, and the silence
/// that follows it.
class SpeechChunk {
  const SpeechChunk(this.text, this.pause);
  final String text;

  /// Silence after this chunk (zero for the last one).
  final Duration pause;

  @override
  String toString() => '"$text" +${pause.inMilliseconds}ms';
}

/// Turns a chat reply into what is spoken: markdown, emoji and stage
/// directions removed, numbers, times, money and abbreviations written out
/// for the language, and the reply cut into sentences with natural pauses
/// between them. Pure text, no platform calls.
class SpeechText {
  SpeechText._();

  /// Silence after a sentence (the owner's brief: 300-450 ms).
  static const Duration sentencePause = Duration(milliseconds: 380);

  /// Silence after a paragraph (a blank line, or a list item).
  static const Duration paragraphPause = Duration(milliseconds: 650);

  /// Silence at a clause boundary inside a very long sentence.
  static const Duration clausePause = Duration(milliseconds: 180);

  /// A sentence longer than this many characters is also cut at a comma,
  /// semicolon or colon, so one breath does not run for ten seconds.
  static const int longSentence = 150;

  /// Step 1: drops markdown, emoji and stage directions. Keeps blank lines
  /// (paragraph breaks) as "\n\n" and joins the other line breaks.
  static String stripMarkup(String text) {
    var t = text.replaceAll('\r', '');
    t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    t = t.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1)!);
    t = t.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!); // links: keep the label
    t = t.replaceAll(RegExp(r'https?://\S+'), ' ');
    t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^\s*>+\s?', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^\s*(?:[-*•–]|\d{1,2}[.)])\s+', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^\s*([-*_=]\s*){3,}$', multiLine: true), '');
    t = t.replaceAll('|', ' ');
    t = t.replaceAll(RegExp(r'\*+|_{2,}|~~'), '');
    // Single underscores around a word (_word_) but not inside_words.
    t = t.replaceAllMapped(RegExp(r'(^|\s)_([^_\s][^_]*)_(?=\s|[.,;:!?]|$)'), (m) => '${m.group(1)}${m.group(2)}');
    t = t.replaceAll(RegExp(r'[#>]'), '');
    // Emoji and pictographs, variation selectors, joiners, keycaps.
    t = t.replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}\u{2900}-\u{297F}\u{2B00}-\u{2BFF}\u{00A9}\u{00AE}\u{203C}\u{2049}\u{2122}\u{2139}\u{FE0F}\u{FE0E}\u{200D}\u{20E3}]', unicode: true), '');
    t = _dropAsides(t);
    t = t.replaceAll(RegExp(r'[ \t ]+'), ' ');
    t = t.replaceAll(RegExp(r' *\n *'), '\n');
    t = t.replaceAll(RegExp(r'\n{2,}'), '\n\n');
    // A single line break is a continuation (soft wrap), unless the line
    // above ended a sentence or a list item: then it is a paragraph.
    t = t.replaceAllMapped(RegExp(r'([^\n])\n(?!\n)([^\n])'), (m) {
      final before = m.group(1)!;
      return RegExp(r'[.!?…:;]').hasMatch(before) ? '$before\n\n${m.group(2)}' : '$before ${m.group(2)}';
    });
    return t.trim();
  }

  /// Short parenthetical asides that are stage directions, "(smiles)",
  /// "(laughs)", "(s)", are removed; longer ones are read with commas.
  static String _dropAsides(String t) {
    return t.replaceAllMapped(RegExp(r'\s*[(\[]([^()\[\]]{0,200})[)\]]'), (m) {
      final inner = m.group(1)!.trim();
      if (inner.isEmpty) return '';
      final words = inner.split(RegExp(r'\s+'));
      final hasDigit = RegExp(r'\d').hasMatch(inner);
      if (words.length <= 3 && !hasDigit && !inner.contains(',')) return '';
      return ', $inner,';
    }).replaceAll(RegExp(r',\s*,'), ',').replaceAllMapped(RegExp(r',\s*([.!?])'), (m) => m.group(1)!);
  }

  /// Step 2: writes times, money, percentages and abbreviations out in
  /// [language], so the synthesizer reads them sensibly and the periods of
  /// "vs." and "etc." do not look like the end of a sentence.
  static String normalize(String text, CoachLanguage language) {
    final es = language == CoachLanguage.es;
    var t = text;

    // Money: $19.99 -> 19 dollars and 99 cents.
    t = t.replaceAllMapped(RegExp(r'([$€£])\s?(\d{1,3}(?:,\d{3})*|\d+)(?:\.(\d{1,2}))?(?!\d)'), (m) {
      final unit = _currency(m.group(1)!, es);
      final whole = m.group(2)!.replaceAll(',', '');
      final cents = m.group(3);
      final c = cents == null ? 0 : int.parse(cents.padRight(2, '0'));
      final main = '$whole ${whole == '1' ? unit.$1 : unit.$2}';
      if (c == 0) return main;
      return es ? '$main con $c ${c == 1 ? 'centavo' : 'centavos'}' : '$main and $c ${c == 1 ? 'cent' : 'cents'}';
    });

    // Percent.
    t = t.replaceAllMapped(RegExp(r'(\d+(?:[.,]\d+)?)\s?%'), (m) => '${m.group(1)} ${es ? 'por ciento' : 'percent'}');

    // Times: 7pm, 7:30 pm, 7 P.M., 19:30.
    t = t.replaceAllMapped(RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s?([AaPp])\.?\s?[Mm]\b'), (m) {
      final hour = int.parse(m.group(1)!);
      final mins = m.group(2);
      final pm = m.group(3)!.toLowerCase() == 'p';
      final clock = mins == null || mins == '00' ? '$hour' : '$hour:$mins';
      if (!es) return '$clock ${pm ? 'p m' : 'a m'}';
      return '$clock ${_esPartOfDay(hour, pm)}';
    });

    // Abbreviations (longest first; before sentence splitting).
    for (final e in (es ? _abbrEs : _abbrEn)) {
      t = t.replaceAllMapped(e.$1, (m) => e.$2);
    }
    t = t.replaceAll('&', es ? ' y ' : ' and ');
    t = t.replaceAll(RegExp(r'\s*\+\s*(?=\d)'), es ? ' más ' : ' plus ');
    t = t.replaceAll(RegExp(r'\s*/\s*'), ' ').replaceAllMapped(RegExp(r'(\d)\s(?=\d)'), (m) => m.group(0)!);
    // 1st, 2nd (English ordinals): the synthesizer handles "1st" poorly.
    if (!es) {
      t = t.replaceAllMapped(RegExp(r'\b(\d+)(st|nd|rd|th)\b'), (m) => _ordinalEn(int.parse(m.group(1)!)));
    }
    // Ellipsis and dashes become a short spoken break.
    t = t.replaceAll(RegExp(r'\.{3,}|…'), '…').replaceAll(RegExp(r'\s*[—–]\s*'), ', ');
    t = t.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAllMapped(RegExp(r' +([,.;:!?])'), (m) => m.group(1)!);
    return t.trim();
  }

  /// Both steps.
  static String clean(String text, CoachLanguage language) => normalize(stripMarkup(text), language);

  /// Step 3: sentences (and paragraphs) as chunks with the pause after each.
  static List<SpeechChunk> chunks(String text) {
    final out = <SpeechChunk>[];
    final paragraphs = text.split(RegExp(r'\n\s*\n')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    for (var p = 0; p < paragraphs.length; p++) {
      final sentences = _sentences(paragraphs[p]);
      for (var s = 0; s < sentences.length; s++) {
        final lastInParagraph = s == sentences.length - 1;
        final lastOverall = lastInParagraph && p == paragraphs.length - 1;
        final isClause = sentences[s].clause;
        out.add(SpeechChunk(
          sentences[s].text,
          lastOverall
              ? Duration.zero
              : lastInParagraph
                  ? paragraphPause
                  : isClause
                      ? clausePause
                      : sentencePause,
        ));
      }
    }
    return out;
  }

  static List<({String text, bool clause})> _sentences(String paragraph) {
    final out = <({String text, bool clause})>[];
    // A terminator (with closing quotes/brackets) followed by a space.
    final parts = paragraph.split(RegExp(r'(?<=[.!?…]["”’)\]]?)\s+(?=["“¿¡(\[]?[\p{L}\p{N}])', unicode: true));
    for (final raw in parts) {
      final s = raw.trim();
      if (s.isEmpty || !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s)) {
        // Punctuation only: glue to the previous chunk.
        if (s.isNotEmpty && out.isNotEmpty) out[out.length - 1] = (text: '${out.last.text} $s', clause: out.last.clause);
        continue;
      }
      if (s.length <= longSentence) {
        out.add((text: s, clause: false));
        continue;
      }
      final pieces = _clauses(s);
      for (var k = 0; k < pieces.length; k++) {
        out.add((text: pieces[k], clause: k < pieces.length - 1));
      }
    }
    return out;
  }

  /// Cuts a long sentence after commas, semicolons and colons, keeping
  /// pieces of at least about 40 characters.
  static List<String> _clauses(String s) {
    final pieces = <String>[];
    var start = 0;
    for (final m in RegExp(r'[,;:]\s+').allMatches(s)) {
      if (m.end - start >= 40 && s.length - m.end >= 25) {
        pieces.add(s.substring(start, m.end).trim());
        start = m.end;
      }
    }
    pieces.add(s.substring(start).trim());
    return pieces;
  }

  // -- tables ---------------------------------------------------------------

  static (String, String) _currency(String symbol, bool es) => switch (symbol) {
        r'$' => es ? ('dólar', 'dólares') : ('dollar', 'dollars'),
        '€' => es ? ('euro', 'euros') : ('euro', 'euros'),
        _ => es ? ('libra', 'libras') : ('pound', 'pounds'),
      };

  static String _esPartOfDay(int hour, bool pm) {
    if (pm) {
      if (hour == 12) return 'del mediodía';
      return hour <= 6 ? 'de la tarde' : 'de la noche';
    }
    if (hour == 12) return 'de la medianoche';
    return hour <= 5 ? 'de la madrugada' : 'de la mañana';
  }

  static String _ordinalEn(int n) {
    const small = {
      1: 'first', 2: 'second', 3: 'third', 4: 'fourth', 5: 'fifth', 6: 'sixth', 7: 'seventh', 8: 'eighth',
      9: 'ninth', 10: 'tenth', 11: 'eleventh', 12: 'twelfth',
    };
    return small[n] ?? '$n';
  }

  static final List<(RegExp, String)> _abbrEn = [
    (RegExp(r'\be\.g\.', caseSensitive: false), 'for example'),
    (RegExp(r'\bi\.e\.', caseSensitive: false), 'that is'),
    (RegExp(r'\betc\.(?=\s+[a-z])'), 'et cetera,'),
    (RegExp(r'\betc\.', caseSensitive: false), 'et cetera.'),
    (RegExp(r'\bvs\.?(?=\s)', caseSensitive: false), 'versus'),
    (RegExp(r'\bapprox\.', caseSensitive: false), 'approximately'),
    (RegExp(r'\bDr\.(?=\s)'), 'Doctor'),
    (RegExp(r'\bMr\.(?=\s)'), 'Mister'),
    (RegExp(r'\bMrs\.(?=\s)'), 'Missus'),
    (RegExp(r'\bMs\.(?=\s)'), 'Miz'),
    (RegExp(r'\bU\.S\.A?\.?'), 'U S'),
    (RegExp(r'\bw/o\b'), 'without'),
    (RegExp(r'\bw/(?=\s)'), 'with'),
    (RegExp(r'\bbtw\b', caseSensitive: false), 'by the way'),
    (RegExp(r'\bASAP\b'), 'as soon as possible'),
    (RegExp(r'\bFYI\b'), 'for your information'),
  ];

  static final List<(RegExp, String)> _abbrEs = [
    (RegExp(r'\bp\.\s?ej\.', caseSensitive: false), 'por ejemplo'),
    (RegExp(r'\betc\.(?=\s+[a-záéíóúñ])'), 'etcétera,'),
    (RegExp(r'\betc\.', caseSensitive: false), 'etcétera.'),
    (RegExp(r'\bvs\.?(?=\s)', caseSensitive: false), 'versus'),
    (RegExp(r'\baprox\.', caseSensitive: false), 'aproximadamente'),
    (RegExp(r'\bEE\.\s?UU\.?'), 'Estados Unidos'),
    (RegExp(r'\bDra\.(?=\s)'), 'Doctora'),
    (RegExp(r'\bDr\.(?=\s)'), 'Doctor'),
    (RegExp(r'\bSra\.(?=\s)'), 'Señora'),
    (RegExp(r'\bSr\.(?=\s)'), 'Señor'),
    (RegExp(r'\bSrta\.(?=\s)'), 'Señorita'),
    (RegExp(r'\bpq\b', caseSensitive: false), 'porque'),
    (RegExp(r'\bxq\b', caseSensitive: false), 'porque'),
    (RegExp(r'\bq\b(?=\s)', caseSensitive: false), 'que'),
    (RegExp(r'\bASAP\b'), 'lo antes posible'),
  ];
}
