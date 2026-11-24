/// Reply options the coach may append to a message as a final line:
///
///     OPTIONS: Safe | "That trail looks unreal." || Playful | "That view beats my Sunday."
///
/// The app shows chips only when this line is present; it never invents them.
class ReplyOption {
  const ReplyOption({required this.label, required this.text});
  final String label;
  final String text;
}

class ParsedReply {
  const ParsedReply(this.body, this.options);
  final String body;
  final List<ReplyOption> options;
}

final RegExp _marker = RegExp(r'(^|\n)\s*OPTIONS\s*:', caseSensitive: false);

ParsedReply parseReply(String text) {
  final match = _marker.allMatches(text).lastOrNull;
  if (match == null) return ParsedReply(text, const []);
  final body = text.substring(0, match.start).trimRight();
  final raw = text.substring(match.end).trim();
  final options = <ReplyOption>[];
  for (final part in raw.split('||')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final bar = p.indexOf('|');
    final label = bar > 0 ? p.substring(0, bar).trim() : '';
    final msg = _unquote(bar > 0 ? p.substring(bar + 1) : p);
    if (msg.isNotEmpty) options.add(ReplyOption(label: label, text: msg));
  }
  return ParsedReply(body, options.take(3).toList());
}

/// [text] as one line of plain text, for previews and accessibility labels:
/// the OPTIONS line is dropped, and markdown markers (`**bold**`, `__`,
/// backticks, `#` headings, `>` quotes, `-`/`*` list dashes) are removed.
String plainPreview(String text) => parseReply(text)
    .body
    .split('\n')
    .map((line) => line.replaceFirst(RegExp(r'^\s*(?:[#>]+\s*|[-*]\s+)'), ''))
    .join(' ')
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _unquote(String s) {
  var t = s.trim();
  const quotes = ['"', '“', '”', "'", '«', '»'];
  while (t.isNotEmpty && quotes.contains(t[0])) {
    t = t.substring(1);
  }
  while (t.isNotEmpty && quotes.contains(t[t.length - 1])) {
    t = t.substring(0, t.length - 1);
  }
  return t.trim();
}
