import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';

/// One official line: what it is (localized), the number as shown, and the
/// link that dials, texts or opens it (null: no single number to call).
class HelpLine {
  const HelpLine(this.label, this.number, this.uri);
  final String Function(AppLocalizations l) label;
  final String? number;
  final String? uri;
}

/// The lines for one country (ISO code, as in `UserProfile.country`).
class HelpCountry {
  const HelpCountry(this.code, this.name, this.lines);
  final String code;
  final String Function(AppLocalizations l) name;
  final List<HelpLine> lines;
}

/// Official crisis, emergency and abuse lines for the four storefronts,
/// checked against the official sources on 2026-11-24 (compliance review F1).
/// The coach prompt gives the same numbers (backend/coach_prompts.js
/// CRISIS_LINES), but this screen works without the AI or a connection.
/// Canada's 9-8-8 is not described as free: the official pages do not say so.
final List<HelpCountry> kHelpCountries = [
  HelpCountry('US', (l) => l.helpCountryUS, [
    HelpLine((l) => l.helpUsSuicide, '988', 'tel:988'),
    HelpLine((l) => l.helpEmergency, '911', 'tel:911'),
    HelpLine((l) => l.helpUsAbuse, '1-800-799-7233', 'tel:+18007997233'),
    HelpLine((l) => l.helpUsAbuseText, '88788', 'sms:88788?body=START'),
  ]),
  HelpCountry('CA', (l) => l.helpCountryCA, [
    HelpLine((l) => l.helpCaSuicide, '9-8-8', 'tel:988'),
    HelpLine((l) => l.helpEmergency, '9-1-1', 'tel:911'),
    HelpLine((l) => l.helpCaAbuse, null, null),
  ]),
  HelpCountry('MX', (l) => l.helpCountryMX, [
    HelpLine((l) => l.helpMxSuicide, '800 911 2000', 'tel:8009112000'),
    HelpLine((l) => l.helpEmergency, '911', 'tel:911'),
    HelpLine((l) => l.helpMxWomen, '079', 'tel:079'),
  ]),
  HelpCountry('ES', (l) => l.helpCountryES, [
    HelpLine((l) => l.helpEsSuicide, '024', 'tel:024'),
    HelpLine((l) => l.helpEmergency, '112', 'tel:112'),
    HelpLine((l) => l.helpEsAbuse, '016', 'tel:016'),
    HelpLine((l) => l.helpEsWhatsApp, '600 000 016', 'https://wa.me/34600000016'),
  ]),
];

/// "Get help now": a static page (no AI, no network needed to read it) with
/// the official lines for the US, Canada, Mexico and Spain. The device's
/// country, when it is one of them, comes first.
class GetHelpScreen extends StatelessWidget {
  const GetHelpScreen({super.key, this.firstCountry});

  /// ISO code of the device region (US, CA, MX, ES), shown first.
  final String? firstCountry;

  static Route<void> route({String? firstCountry}) =>
      MaterialPageRoute<void>(builder: (_) => GetHelpScreen(firstCountry: firstCountry));

  Future<void> _open(String uri) async {
    try {
      await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
    } catch (_) {
      // The number stays on screen to dial by hand.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final countries = [
      ...kHelpCountries.where((c) => c.code == firstCountry),
      ...kHelpCountries.where((c) => c.code != firstCountry),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(l.getHelpNow)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              key: const ValueKey('get-help-list'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                WholeWordsText(l.getHelpIntro, key: const ValueKey('get-help-intro'), style: AppText.body),
                for (final c in countries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
                    child: Semantics(
                      header: true,
                      child: Text(c.name(l), key: ValueKey('help-country-${c.code}'), style: AppText.name.copyWith(fontSize: 20)),
                    ),
                  ),
                  DwCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      // Every row spans the card, so short rows stay left-aligned with the others.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < c.lines.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _LineTile(
                            key: ValueKey('help-${c.code}-$i'),
                            line: c.lines[i],
                            onTap: c.lines[i].uri == null ? null : () => _open(c.lines[i].uri!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(l.helpFootnote, key: const ValueKey('get-help-footnote'), style: AppText.small),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({super.key, required this.line, this.onTap});
  final HelpLine line;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final number = line.number;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (number != null)
                Text(number,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.gold, height: 1.3)),
              Text(line.label(l), style: const TextStyle(fontSize: 14.5, height: 1.4, color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}
