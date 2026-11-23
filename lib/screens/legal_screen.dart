import 'package:flutter/material.dart';

import '../content/legal_text.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// The in-app legal documents.
enum LegalDoc { privacy, terms }

/// A clean, readable legal/document page. Renders lightweight markup:
/// - lines starting with "# " become section headings
/// - lines starting with "- " become bullet points (with a bold lead-in label
///   when the item starts with a short "Label:" prefix)
/// - the first "Last updated" line is shown as muted sub-text
/// - blank lines separate paragraphs
///
/// [LegalScreen.doc] shows a document in the UI language: in Spanish, the
/// Spanish translation with a note that the English version governs.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required String this.title, required String this.content}) : doc = null;
  const LegalScreen.doc(LegalDoc this.doc, {super.key})
      : title = null,
        content = null;

  final String? title;
  final String? content;
  final LegalDoc? doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final es = Localizations.localeOf(context).languageCode == 'es';
    final title = this.title ?? (doc == LegalDoc.terms ? l.termsOfUse : l.privacyPolicy);
    final content = this.content ??
        switch ((doc!, es)) {
          (LegalDoc.privacy, false) => kPrivacyPolicy,
          (LegalDoc.terms, false) => kTermsOfService,
          (LegalDoc.privacy, true) => kPrivacyPolicyEs,
          (LegalDoc.terms, true) => kTermsOfServiceEs,
        };
    final note = doc != null && es ? l.legalTranslationNote : '';
    final lines = content.trim().split('\n');

    final widgets = <Widget>[];
    var firstHeadingSeen = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.isEmpty) {
        widgets.add(const SizedBox(height: AppSpacing.sm));
        continue;
      }

      // "Last updated: ..." intro line → muted chip-like sub-text.
      if (i == 0 && (line.toLowerCase().startsWith('last updated') || line.startsWith('Última actualización'))) {
        widgets.add(Text(
          line,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ));
        if (note.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(note, key: const ValueKey('legal-translation-note'), style: AppText.small.copyWith(color: AppColors.textMuted)),
          ));
        }
        widgets.add(const SizedBox(height: AppSpacing.md));
        continue;
      }

      // Section heading.
      if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: EdgeInsets.only(
            top: firstHeadingSeen ? AppSpacing.lg : AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            line.substring(2),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              height: 1.25,
            ),
          ),
        ));
        firstHeadingSeen = true;
        continue;
      }

      // Bullet point.
      if (line.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 10, left: 2),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(child: _bulletText(theme, line.substring(2))),
            ],
          ),
        ));
        continue;
      }

      // Regular paragraph.
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          line,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
        ),
      ));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widgets,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Renders a bullet's text, bolding a short "Label:" lead-in when present
  /// (e.g. "Account information (optional): ...") for scannability.
  Widget _bulletText(ThemeData theme, String text) {
    final base = theme.textTheme.bodyMedium?.copyWith(height: 1.5);
    final lead = legalLeadIn(text);
    if (lead > 0) {
      final label = text.substring(0, lead);
      final rest = text.substring(lead);
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(
                text: label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: rest),
          ],
        ),
      );
    }
    return Text(text, style: base);
  }
}
