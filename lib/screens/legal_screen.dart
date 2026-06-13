import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A simple, scrollable legal/document page. Renders lightweight markup: lines
/// starting with "# " become section headings; blank lines separate paragraphs.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = content.trim().split('\n');

    final widgets = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: AppSpacing.sm));
      } else if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: 4),
          child: Text(
            line.substring(2),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ));
      } else {
        widgets.add(Text(
          line,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ));
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widgets,
            ),
          ),
        ),
      ),
    );
  }
}
