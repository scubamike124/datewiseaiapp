// The hosted legal pages are generated from the in-app text and must match it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/legal_pages.dart';

void main() {
  test('web legal pages (EN + ES) are up to date with lib/content/legal_text.dart', () {
    expect(legalPages.map((p) => p.file),
        ['web/privacy.html', 'web/terms.html', 'web/privacy-es.html', 'web/terms-es.html']);
    for (final p in legalPages) {
      expect(File(p.file).readAsStringSync(), renderPage(p),
          reason: '${p.file} is stale: run `dart run tool/legal_pages.dart`');
    }
  });

  test('no v1 claims remain on the hosted pages', () {
    for (final p in legalPages) {
      final html = File(p.file).readAsStringSync().toLowerCase();
      for (final v1 in ['photo-analysis', 'photos, and messaging', 'delete your account', 'supabase', 'gemini']) {
        expect(html.contains(v1), isFalse, reason: '${p.file}: "$v1"');
      }
    }
  });
}
