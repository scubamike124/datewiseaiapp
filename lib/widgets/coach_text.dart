import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Minimal markdown renderer for coach messages. Supports the subset DateWise AI
/// actually emits (PRD voice guidelines): **bold**, bullet lists (`• `/`- `),
/// numbered lists (`1. `), and blockquotes (`> `). Avoids a heavy markdown
/// dependency for what is a small, well-known grammar. Every block uses
/// Text.rich, so replies follow the system text size (Dynamic Type).
class CoachText extends StatelessWidget {
  const CoachText(this.text, {super.key, this.color});

  /// Typographic quotes, matching the suggestion chips: "a" → “a”, it's →
  /// it’s. A double quote opens at the start or after a space or opening
  /// punctuation, and closes otherwise. Bold markers (**) are left alone.
  static String smartQuotes(String s) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      final prev = i == 0 ? '' : s[i - 1];
      final opens = prev.isEmpty || RegExp(r'[\s(\[{¿¡*—–-]').hasMatch(prev);
      if (c == '"') {
        out.write(opens ? '\u201C' : '\u201D');
      } else if (c == "'") {
        out.write(opens ? '\u2018' : '\u2019');
      } else {
        out.write(c);
      }
    }
    return out.toString();
  }

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge!.copyWith(
          color: color ?? AppColors.text,
          fontSize: 15,
          height: 1.45,
        );
    final lines = smartQuotes(text).split('\n');
    final blocks = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        blocks.add(const SizedBox(height: 8));
        continue;
      }
      if (trimmed.startsWith('> ')) {
        blocks.add(_quote(trimmed.substring(2), base));
      } else if (trimmed.startsWith('• ') || trimmed.startsWith('- ')) {
        blocks.add(_bullet(trimmed.substring(2), base));
      } else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        final idx = trimmed.indexOf('. ');
        blocks.add(_numbered(trimmed.substring(0, idx), trimmed.substring(idx + 2), base));
      } else {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(_inline(trimmed, base)),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  Widget _quote(String content, TextStyle base) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: const Border(
          left: BorderSide(color: AppColors.accent, width: 3),
        ),
      ),
      child: Text.rich(_inline(content, base.copyWith(fontStyle: FontStyle.italic))),
    );
  }

  Widget _bullet(String content, TextStyle base) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 6, color: AppColors.primary),
          ),
          Expanded(child: Text.rich(_inline(content, base))),
        ],
      ),
    );
  }

  Widget _numbered(String number, String content, TextStyle base) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('$number.',
                style: base.copyWith(
                    fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
          Expanded(child: Text.rich(_inline(content, base))),
        ],
      ),
    );
  }

  /// Parses **bold** spans within a line.
  TextSpan _inline(String content, TextStyle base) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var last = 0;
    for (final match in pattern.allMatches(content)) {
      if (match.start > last) {
        spans.add(TextSpan(text: content.substring(last, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      last = match.end;
    }
    if (last < content.length) {
      spans.add(TextSpan(text: content.substring(last)));
    }
    return TextSpan(style: base, children: spans);
  }
}
