// CI hygiene: third-party actions pinned to commit SHAs, one Flutter version
// everywhere, and signing secrets only in the steps that use them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflows = Directory('.github/workflows')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
      .toList();

  test('every action is pinned to a full commit SHA with a version comment', () {
    expect(workflows, isNotEmpty);
    for (final f in workflows) {
      for (final m in RegExp(r'uses:\s*(\S+)(.*)$', multiLine: true).allMatches(f.readAsStringSync())) {
        final ref = m[1]!;
        if (ref.startsWith('./')) continue; // local action
        expect(RegExp(r'^[\w.-]+/[\w./-]+@[0-9a-f]{40}$').hasMatch(ref), isTrue, reason: '${f.path}: $ref');
        expect(RegExp(r'#\s*v\d').hasMatch(m[2]!), isTrue, reason: '${f.path}: $ref needs a version comment');
      }
    }
  });

  test('every Flutter setup uses the same pinned version', () {
    final versions = <String>{};
    for (final f in workflows) {
      final s = f.readAsStringSync();
      if (!s.contains('subosito/flutter-action')) continue;
      final v = RegExp(r"FLUTTER_VERSION:\s*'([\d.]+)'").firstMatch(s);
      expect(v, isNotNull, reason: f.path);
      versions.add(v![1]!);
      final setups = RegExp('subosito/flutter-action').allMatches(s).length;
      expect(RegExp(r'flutter-version: \$\{\{ env\.FLUTTER_VERSION \}\}').allMatches(s).length, setups, reason: f.path);
    }
    expect(versions, {'3.47.9'});
    expect(File('netlify.toml').readAsStringSync(), contains('-b 3.47.9'));
  });

  test('ios-build.yml: no job-level secrets; signing files removed in an always() step', () {
    final s = File('.github/workflows/ios-build.yml').readAsStringSync();
    final job = s.substring(s.indexOf('  signed-testflight:'));
    final beforeSteps = job.substring(0, job.indexOf('    steps:'));
    expect(beforeSteps, isNot(contains('secrets.')));
    // Each secret value is mapped only into the step(s) that use it.
    expect(RegExp(r'secrets\.APP_STORE_CONNECT_API_KEY_P8 \}\}').allMatches(job).length, 1);
    expect(RegExp(r'secrets\.IOS_DIST_CERT_P12_BASE64 \}\}').allMatches(job).length, 1);
    final cleanup = job.substring(job.indexOf('- name: Clean up signing material'));
    expect(cleanup, contains('if: always()'));
    for (final file in ['signing.keychain-db', 'dist.p12', 'profile.mobileprovision', '.appstoreconnect/private_keys', r'$PROFILE_UUID.mobileprovision']) {
      expect(cleanup, contains(file));
    }
    expect(job, isNot(contains('--upload-app')), reason: 'deprecated; use --upload-package');
    expect(job, contains('xcrun altool --upload-package'));
  });

  test('build numbers: pubspec 100, CI 100 + run number, checklist agrees', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('\nversion: 2.0.0+100\n'));
    expect(File('.github/workflows/ios-build.yml').readAsStringSync(), contains(r'BUILD_NUMBER=$((100 + GITHUB_RUN_NUMBER))'));
    final checklist = File('docs/appstore/checklist.md').readAsStringSync();
    expect(checklist, contains('build **100**'));
    expect(checklist, contains('`version: 2.0.0+100`'));
    expect(checklist, isNot(contains('2.0.0+4')));
  });

  test('billing grace: off in App Store Connect and 0 on the backend', () {
    expect(File('backend/wrangler.toml').readAsStringSync(), contains('BILLING_GRACE_DAYS = "0"'));
    final checklist = File('docs/appstore/checklist.md').readAsStringSync();
    expect(checklist, contains('**Billing Grace Period: keep it OFF**'));
    expect(checklist, contains('covers the **purchase UI only**'));
  });
}
