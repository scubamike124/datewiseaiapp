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

  test('model-eval: spends only behind the model-eval environment, with secrets the deploy check never sees', () {
    final s = File('.github/workflows/model-eval.yml').readAsStringSync();
    final secrets = RegExp(r'secrets\.(\w+)').allMatches(s).map((m) => m[1]).toSet();
    expect(secrets, {'DW_EVAL_CF_AI_TOKEN', 'DW_EVAL_CF_ACCOUNT_ID'});
    final live = s.substring(s.indexOf('\n  live:'));
    expect(live, contains('environment: model-eval'));
    expect(live, contains('secrets.DW_EVAL_CF_AI_TOKEN'));
    expect(s.substring(0, s.indexOf('\n  live:')), isNot(contains('secrets.')));
    // deploy-worker.yml refuses these as repository secrets; the eval must never ask for them.
    for (final name in ['CLOUDFLARE_ACCOUNT_ID', 'CLOUDFLARE_API_TOKEN', 'ID_HASH_SALT']) {
      expect(secrets, isNot(contains(name)));
    }
  });

  group('deploy-worker.yml: the staging target', () {
    final s = File('.github/workflows/deploy-worker.yml').readAsStringSync();
    final deployJob = s.substring(s.indexOf('\n  deploy:\n'));

    test('chat-v7-staging is a dispatch choice; tags stay v7/v6 and refuse "staging"', () {
      expect(s, contains('          - chat-v7-cost-guard\n          - chat-v6\n          - chat-v7-staging\n        default: chat-v7-cost-guard'));
      expect(s, contains("    tags:\n      - 'worker-v7-*'\n      - 'worker-v6-*'\n\npermissions:"));
      expect(s, contains(r'''[[ "${REF_NAME,,}" != *staging* ]] || die'''));
      // Dry run stays the default.
      expect(s, contains("dry_run:\n        description: 'Dry run only (bundle and checks, no upload). Untick to deploy after the owner approves.'\n        type: boolean\n        default: true"));
    });

    test('Worker names are constants; staging never uses the production name', () {
      expect(s, contains('  WORKER_NAME: datewise-photo-coach\n'));
      expect(s, contains('  STAGING_WORKER_NAME: datewise-coach-staging\n'));
      expect(s, contains('chat-v7-staging)    cf_env=staging;    expect=chat-v7-cost-guard; worker="\$STAGING_WORKER_NAME"; envflag=" --env staging" ;;'));
      expect(s, contains('[ "\$worker" != "\$WORKER_NAME" ] || { echo "::error::the staging Worker name must differ from production"; exit 1; }'));
      // The deploy job re-checks [env.staging] name before deploying.
      expect(deployJob, contains("ok = name == os.environ['STAGING_WORKER_NAME'] and name != cfg.get('name') and name != os.environ['WORKER_NAME']"));
    });

    test('every protection applies to staging: main-ancestor commits, one approval environment', () {
      expect(s, contains('  REVIEWED_BRANCH: main\n'));
      // Exactly one environment, the protected one, for every target.
      expect(RegExp(r'^\s+environment:', multiLine: true).allMatches(s).length, 1);
      expect(deployJob, contains('    environment: production-worker\n'));
      // The workflow commit is checked for every target; the staging code commit like chat-v7.
      expect(RegExp(r'on_main "\$GITHUB_SHA" \|\|').allMatches(s).length, 2);
      expect(deployJob, contains('if [ "\$TARGET" = "chat-v7-cost-guard" ] || [ "\$TARGET" = "chat-v7-staging" ]; then\n            on_main "\$SHA"'));
      // Never the chat-v6 commit or flag.
      expect('chat-v7-staging never deploys the chat-v6 commit'.allMatches(s).length, 3);
      expect('force_v6_over_unknown is for chat-v6 only'.allMatches(s).length, 2);
    });

    test('--env staging appears only on staging paths', () {
      for (final line in s.split('\n').where((l) => l.contains('--env staging'))) {
        final t = line.trim();
        final ok = t.startsWith('#') ||
            t.startsWith('echo ') ||
            t.startsWith('if [ "\$CF_ENV" = "staging" ]; then echo ') ||
            t.startsWith('fail()') ||
            t == 'staging) args=(--env staging) ;;' ||
            t == 'args=(); [ "\$CF_ENV" = "staging" ] && args=(--env staging)' ||
            t.startsWith('chat-v7-staging)    cf_env=staging;') ||
            t.contains('secret list --env staging') ||
            t.startsWith("command: \${{ format('deploy{0}{1}', needs.check.outputs.target == 'chat-v7-staging' && ' --env staging' || ''");
        expect(ok, isTrue, reason: line);
      }
    });

    test('staging salt is random and never production\'s; staging URL never WORKER_URL', () {
      final salt = deployJob.substring(deployJob.indexOf('- name: Staging ID_HASH_SALT'), deployJob.indexOf('- name: Deploy with Wrangler'));
      expect(salt, contains("if: needs.check.outputs.target == 'chat-v7-staging'"));
      expect(salt, isNot(contains('secrets.ID_HASH_SALT')));
      expect(salt, contains('randomBytes(32)'));
      expect(salt, isNot(contains('console.log')));
      // The production salt step is still for chat-v7-cost-guard only.
      expect(deployJob, contains("id: salt\n        if: needs.check.outputs.target == 'chat-v7-cost-guard'"));
      expect(deployJob, contains('[ "\$CF_ENV" = "staging" ] && url=""'));
      expect(deployJob, contains(r'[[ "$url" =~ ^https://${STAGING_WORKER_NAME}\.[a-z0-9-]+\.workers\.dev$ ]]'));
    });

    test('staging post-deploy check: version, 403 SUBSCRIPTION_REQUIRED, JWS check, v1 off', () {
      final post = deployJob.substring(deployJob.indexOf('- name: Post-deploy checks (staging only, no AI is used)'));
      expect(post, contains("if: needs.check.outputs.target == 'chat-v7-staging'"));
      expect(post, contains('[ "\$got" = "chat-v7-cost-guard" ]'));
      expect(post, contains('[ "\$code" = "403" ] && [ "\$body_code" = "SUBSCRIPTION_REQUIRED" ]'));
      expect(post, contains('[ "\$code" = "403" ] && [ "\$body_code" = "SUBSCRIPTION_INVALID" ]'));
      expect(post, contains('[ "\$hdr" = "APP_UPDATE_REQUIRED" ]'));
      expect(post, contains('delete --env staging'));
      // The shared post-deploy check runs the 403 check for staging too.
      expect(deployJob, contains('if [ "\$TARGET" = "chat-v7-cost-guard" ] || [ "\$TARGET" = "chat-v7-staging" ]; then\n            # A v2 chat request with no StoreKit token'));
    });

    test('the wrangler.toml checks validate [env.staging] and the dry run builds it', () {
      expect(s, contains("if 'staging' in envs: check_staging(envs['staging'] or {}, vars_)"));
      expect(s, contains("elif target == 'chat-v7-staging': errors.append('[env.staging] is missing')"));
      expect(s, contains("if: steps.plan.outputs.target == 'chat-v7-cost-guard' || steps.plan.outputs.target == 'chat-v7-staging'"));
      expect(s, contains(r"""need 'env\.SANDBOX_NEURON_BUDGET \("3000"\)' 'SANDBOX_NEURON_BUDGET 3000'"""));
      expect(s, contains('EXPECT: \${{ steps.plan.outputs.expect }}'));
    });
  });
}
