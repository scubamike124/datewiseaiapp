// Generates the hosted legal pages from the in-app text, so the website and
// the app say exactly the same thing:
//
//   web/privacy.html, web/terms.html          (English, the governing text)
//   web/privacy-es.html, web/terms-es.html    (Spanish translation)
//   web/support.html, web/support-es.html     (customer support page, the
//                                             App Store Support URL)
//
// Source: lib/content/legal_text.dart and lib/content/support_text.dart.
// Regenerate after editing either:
//
//   dart run tool/legal_pages.dart
//
// test/legal_pages_test.dart fails when the pages are out of date.

import 'dart:io';

import 'package:datewise_ai/content/legal_text.dart';
import 'package:datewise_ai/content/support_text.dart';

class LegalPage {
  const LegalPage({
    required this.file,
    required this.lang,
    required this.title,
    required this.description,
    required this.text,
    required this.updated,
    required this.otherLabel,
    required this.otherHref,
    required this.languageLabel,
    required this.languageHref,
    required this.rights,
  });

  final String file;
  final String lang;
  final String title;
  final String description;
  final String text;
  final String updated;
  final String otherLabel;
  final String otherHref;
  final String languageLabel;
  final String languageHref;
  final String rights;
}

final legalPages = [
  LegalPage(
    file: 'web/privacy.html',
    lang: 'en',
    title: 'Privacy Policy',
    description: 'DateWise AI Privacy Policy: what information the app handles, how it is used, and your choices.',
    text: kPrivacyPolicy,
    updated: kPrivacyLastUpdated,
    otherLabel: 'Terms of Use',
    otherHref: '/terms-of-service',
    languageLabel: 'Español',
    languageHref: '/privacy-es.html',
    rights: 'All rights reserved.',
  ),
  LegalPage(
    file: 'web/terms.html',
    lang: 'en',
    title: 'Terms of Use',
    description: 'DateWise AI Terms of Use.',
    text: kTermsOfService,
    updated: kLegalLastUpdated,
    otherLabel: 'Privacy Policy',
    otherHref: '/privacy-policy',
    languageLabel: 'Español',
    languageHref: '/terms-es.html',
    rights: 'All rights reserved.',
  ),
  LegalPage(
    file: 'web/privacy-es.html',
    lang: 'es',
    title: 'Política de privacidad',
    description: 'Política de privacidad de DateWise AI. Traducción; el texto en inglés es el que rige.',
    text: kPrivacyPolicyEs,
    updated: kPrivacyLastUpdatedEs,
    otherLabel: 'Términos de uso',
    otherHref: '/terms-es.html',
    languageLabel: 'English',
    languageHref: '/privacy-policy',
    rights: 'Todos los derechos reservados.',
  ),
  LegalPage(
    file: 'web/terms-es.html',
    lang: 'es',
    title: 'Términos de uso',
    description: 'Términos de uso de DateWise AI. Traducción; el texto en inglés es el que rige.',
    text: kTermsOfServiceEs,
    updated: kLegalLastUpdatedEs,
    otherLabel: 'Política de privacidad',
    otherHref: '/privacy-es.html',
    languageLabel: 'English',
    languageHref: '/terms-of-service',
    rights: 'Todos los derechos reservados.',
  ),
];

/// The customer support pages (the App Store Support URL), rendered with the
/// same template as the legal pages.
final supportPages = [
  LegalPage(
    file: 'web/support.html',
    lang: 'en',
    title: 'Support',
    description: 'DateWise AI customer support: contact us, subscriptions, refunds, restoring purchases and your data.',
    text: kSupportPage,
    updated: kSupportLastUpdated,
    otherLabel: 'Privacy Policy',
    otherHref: '/privacy-policy',
    languageLabel: 'Español',
    languageHref: '/support-es.html',
    rights: 'All rights reserved.',
  ),
  LegalPage(
    file: 'web/support-es.html',
    lang: 'es',
    title: 'Soporte',
    description: 'Soporte de DateWise AI: contacto, suscripciones, reembolsos, restaurar compras y tus datos.',
    text: kSupportPageEs,
    updated: kSupportLastUpdatedEs,
    otherLabel: 'Política de privacidad',
    otherHref: '/privacy-es.html',
    languageLabel: 'English',
    languageHref: '/support.html',
    rights: 'Todos los derechos reservados.',
  ),
];

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Escapes [s] and turns e-mail addresses and https URLs into links.
String _inline(String s) {
  final out = StringBuffer();
  final link = RegExp(r'(https://[^\s,;)]+[^\s,;).])|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})');
  var last = 0;
  for (final m in link.allMatches(s)) {
    out.write(_esc(s.substring(last, m.start)));
    final v = m[0]!;
    final href = m[1] != null ? v : 'mailto:$v';
    out.write('<a href="${_esc(href)}">${_esc(v)}</a>');
    last = m.end;
  }
  out.write(_esc(s.substring(last)));
  return out.toString();
}

/// The page body from the in-app format: "# " headings, "- " list items,
/// other lines as paragraphs (consecutive lines joined with a line break).
String renderBody(String text, String updated) {
  final lines = text.split('\n').map((l) => l.trimRight()).toList();
  final out = StringBuffer();
  final para = <String>[];
  final list = <String>[];
  var intro = true;

  void flush() {
    if (para.isNotEmpty) {
      final cls = intro ? ' class="intro"' : '';
      out.writeln('      <p$cls>${para.map(_inline).join('<br />\n      ')}</p>');
      para.clear();
    }
    if (list.isNotEmpty) {
      out.writeln('      <ul>');
      for (final li in list) {
        final lead = legalLeadIn(li);
        final label = lead > 0 ? '<strong>${_inline(li.substring(0, lead))}</strong>' : '';
        out.writeln('        <li>$label${_inline(li.substring(lead))}</li>');
      }
      out.writeln('      </ul>');
      list.clear();
    }
  }

  for (final line in lines) {
    if (line == updated) continue; // shown in the header
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('# ')) {
      flush();
      intro = false;
      out.writeln();
      out.writeln('      <h2>${_inline(line.substring(2))}</h2>');
    } else if (line.startsWith('- ')) {
      if (para.isNotEmpty) flush();
      list.add(line.substring(2));
    } else {
      if (list.isNotEmpty) flush();
      para.add(line);
    }
  }
  flush();
  return out.toString();
}

String renderPage(LegalPage p) => '''
<!DOCTYPE html>
<!-- Generated from lib/content/legal_text.dart by tool/legal_pages.dart. Do not edit by hand. -->
<html lang="${p.lang}">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${_esc(p.title)} — DateWise AI</title>
  <meta name="description" content="${_esc(p.description)}" />
  <meta name="robots" content="index,follow" />
  <style>
    :root{
      --ink:#1b1730; --body:#332f47; --muted:#6b6880; --line:#eceaf2;
      --accent:#e0457b; --accent2:#7a3df2; --bg:#ffffff; --soft:#faf8fc;
    }
    *{box-sizing:border-box;}
    html{scroll-behavior:smooth;}
    body{
      margin:0; background:var(--soft); color:var(--body);
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
      line-height:1.7; -webkit-font-smoothing:antialiased;
    }
    .hero{
      background:linear-gradient(135deg,var(--accent) 0%,var(--accent2) 100%);
      color:#fff; padding:46px 22px 40px;
    }
    .hero-in{max-width:780px; margin:0 auto;}
    .brand{font-weight:800; letter-spacing:.02em; font-size:.95rem; opacity:.95; text-transform:uppercase;}
    .hero h1{margin:10px 0 6px; font-size:2.1rem; letter-spacing:-.01em;}
    .hero .updated{margin:0; opacity:.9; font-size:.95rem;}
    .hero .lang{color:#fff; opacity:.9; font-size:.9rem;}
    main{max-width:780px; margin:-22px auto 0; padding:0 22px 72px;}
    .card{
      background:var(--bg); border:1px solid var(--line); border-radius:16px;
      padding:30px 30px 8px; box-shadow:0 12px 40px rgba(40,20,80,.06);
    }
    .intro{font-size:1.06rem; color:var(--ink); margin-top:4px;}
    h2{
      font-size:1.18rem; color:var(--ink); margin:30px 0 10px;
      padding-top:18px; border-top:1px solid var(--line);
    }
    h2:first-of-type{border-top:0; padding-top:0;}
    p{margin:0 0 14px;}
    ul{margin:0 0 16px; padding-left:1.2rem;}
    li{margin:8px 0;}
    a{color:var(--accent); text-decoration:none;}
    a:hover{text-decoration:underline;}
    .foot{
      max-width:780px; margin:0 auto; padding:8px 22px 40px;
      color:var(--muted); font-size:.9rem; text-align:center;
    }
    .foot a{color:var(--muted);}
    @media(max-width:560px){
      .hero h1{font-size:1.7rem;}
      .card{padding:24px 20px 6px;}
    }
  </style>
</head>
<body>
  <header class="hero">
    <div class="hero-in">
      <div class="brand">DateWise AI</div>
      <h1>${_esc(p.title)}</h1>
      <p class="updated">${_esc(p.updated)}</p>
      <a class="lang" href="${p.languageHref}" hreflang="${p.lang == 'en' ? 'es' : 'en'}">${_esc(p.languageLabel)}</a>
    </div>
  </header>

  <main>
    <div class="card">
${renderBody(p.text, p.updated).trimRight()}
    </div>
  </main>

  <p class="foot">&copy; 2026 DateWise AI. ${_esc(p.rights)} &middot; <a href="${p.otherHref}">${_esc(p.otherLabel)}</a></p>
</body>
</html>
''';

void main() {
  for (final p in [...legalPages, ...supportPages]) {
    File(p.file).writeAsStringSync(renderPage(p));
    stdout.writeln('wrote ${p.file}');
  }
}
