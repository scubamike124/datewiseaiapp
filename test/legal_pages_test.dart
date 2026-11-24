// The hosted legal pages are generated from the in-app text and must match it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/app_links.dart';

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

  test('bullet lead-ins are bold on the web pages too (ES Coach memory included)', () {
    final es = File('web/privacy-es.html').readAsStringSync();
    expect(es, contains('<strong>Memoria del coach (opcional, desactivada por defecto):</strong>'));
    expect(File('web/privacy.html').readAsStringSync(), contains('<strong>Coach memory (optional, off by default):</strong>'));
  });

  test('the portraits are described as AI-generated images of fictional characters', () {
    expect(File('web/terms.html').readAsStringSync(),
        contains('AI-generated images of fictional coach characters; they do not depict real people'));
    expect(File('web/terms-es.html').readAsStringSync(),
        contains('imágenes generadas por IA de personajes ficticios; no representan a personas reales'));
    for (final f in ['web/terms.html', 'web/terms-es.html']) {
      expect(File(f).readAsStringSync(), isNot(contains('ilustraciones')));
      expect(File(f).readAsStringSync(), isNot(contains('illustrations')));
    }
  });

  test('the URLs in AppLinks serve the generated pages (Netlify and Apache rules)', () {
    final redirects = File('web/_redirects').readAsStringSync();
    final htaccess = File('web/.htaccess').readAsStringSync();
    for (final (url, file) in [(AppLinks.privacyPolicyUrl, 'privacy.html'), (AppLinks.termsUrl, 'terms.html')]) {
      final path = Uri.parse(url).path; // /privacy-policy, /terms-of-service
      expect(url, startsWith('https://datewise-legal.lovable.app/'));
      expect(File('web/$file').existsSync(), isTrue);
      expect(RegExp('^${RegExp.escape(path)}\\s+/${RegExp.escape(file)}\\s+200\$', multiLine: true).hasMatch(redirects), isTrue,
          reason: '$path must map to /$file before the SPA fallback');
      expect(redirects.indexOf(path), lessThan(redirects.indexOf('/*')));
      expect(htaccess, contains('RewriteRule ^${path.substring(1)}/?\$ $file'));
    }
  });

  test('support pages (EN + ES) are up to date and give real customer support', () {
    expect(supportPages.map((p) => p.file), ['web/support.html', 'web/support-es.html']);
    for (final p in supportPages) {
      final html = File(p.file).readAsStringSync();
      expect(html, renderPage(p), reason: '${p.file} is stale: run `dart run tool/legal_pages.dart`');
      expect(html, contains('<a href="mailto:${AppLinks.supportEmail}">'), reason: '${p.file}: support email');
      expect(html, contains('reportaproblem.apple.com'), reason: '${p.file}: refunds');
    }
    expect(AppLinks.supportUrl, 'https://datewise-legal.lovable.app/support.html');
    expect(AppLinks.supportUrl, isNot(AppLinks.termsUrl));
  });

  test('the privacy pages describe the AI consent step and how to withdraw it', () {
    final en = File('web/privacy.html').readAsStringSync();
    final es = File('web/privacy-es.html').readAsStringSync();
    expect(en, contains('Nothing is sent to the AI provider until you tap Agree.'));
    expect(en, contains('<strong>Withdrawing your permission:</strong>'));
    expect(en, contains("Cloudflare Workers AI, which runs Meta's Llama model"));
    expect(es, contains('No se envía nada al proveedor de IA hasta que tocas Aceptar.'));
    expect(es, contains('<strong>Retirar tu permiso:</strong>'));
    expect(es, contains('modelo Llama de Meta'));
  });
}
