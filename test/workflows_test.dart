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

  test('pull requests compile the same web build that deploy.yml publishes from main', () {
    final cmd = RegExp(r'run: (flutter build web[^\n]*)');
    final deploy = cmd.firstMatch(File('.github/workflows/deploy.yml').readAsStringSync())![1];
    final tests = File('.github/workflows/test.yml').readAsStringSync();
    expect(tests, contains('run: $deploy\n'));
    expect(tests, isNot(contains('--dart-define')));
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
    // The .p8: once for the cloud-signing export, once for the TestFlight upload.
    expect(RegExp(r'secrets\.APP_STORE_CONNECT_API_KEY_P8 \}\}').allMatches(job).length, 2);
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

  group('ios-build.yml: TestFlight build against the staging coach Worker', () {
    final s = File('.github/workflows/ios-build.yml').readAsStringSync();
    final unsigned = s.substring(s.indexOf('  unsigned:'), s.indexOf('  signed-testflight:'));
    final job = s.substring(s.indexOf('  signed-testflight:'));
    final build = job.substring(job.indexOf('- name: flutter build ipa'), job.indexOf('- uses: actions/upload-artifact'));
    const stagingUrl = 'https://datewise-coach-staging.scubamike124.workers.dev';

    test('coach_backend is a choice input, production by default (never a free-form URL)', () {
      expect(s, contains("      coach_backend:\n"));
      expect(s, contains('        type: choice\n        options:\n          - production\n          - staging\n        default: production\n'));
      expect(RegExp(r'^\s+\w+:\n\s+description:[^\n]*\n\s+type: string', multiLine: true).hasMatch(s), isFalse,
          reason: 'no free-form string inputs');
    });

    test('the input reaches the shell only through env:, and the URL is a constant', () {
      expect(RegExp(r'\$\{\{ *inputs\.coach_backend *\}\}').allMatches(s).length, 1);
      expect(build, contains('COACH_BACKEND: \${{ inputs.coach_backend }}'));
      // No ${{ }} expression inside any run: block.
      for (final m in RegExp(r'run: \|\n((?:          .*\n|\n)+)').allMatches(s)) {
        expect(m[1], isNot(contains(r'${{')), reason: m[1]);
      }
      expect(build, contains('STAGING_COACH_URL="$stagingUrl"'));
      expect(build, contains(r'staging) DEFINES+=(--dart-define=COACH_BACKEND_URL="$STAGING_COACH_URL") ;;'));
      expect(build, contains(r'*) echo "::error::Unknown coach_backend"; exit 1 ;;'));
      expect(build, contains(r'"${DEFINES[@]}"'));
      expect(RegExp('COACH_BACKEND_URL=').allMatches(s).length, 2, reason: 'one define, one summary line');
      // Production keeps the app's built-in production URL (no define).
      expect(build, contains('production|"") COACH_BACKEND=production ;;'));
      // The staging host matches the app's production subdomain.
      final appUrl = RegExp(r"productionUrl = '([^']+)'").firstMatch(File('lib/services/ai_config.dart').readAsStringSync())![1]!;
      expect(Uri.parse(appUrl).host.split('.').sublist(1), Uri.parse(stagingUrl).host.split('.').sublist(1));
    });

    test('staging builds get their own +50000 build-number range and a loud summary', () {
      expect(build, contains(r'BUILD_NUMBER=$((100 + GITHUB_RUN_NUMBER))'));
      expect(build, contains(r'BUILD_NUMBER=$((5000 + BUILD_NUMBER))'));
      expect(build, contains(r'BUILD_NUMBER=$((50000 + BUILD_NUMBER))'));
      expect(build.indexOf('50000 + BUILD_NUMBER'), greaterThan(build.indexOf('5000 + BUILD_NUMBER')));
      expect(build, contains('STAGING COACH BUILD'));
      expect(build, contains('do NOT submit for App Store review'));
      expect(job, contains("\${{ inputs.coach_backend == 'staging' && 'datewise-ios-ipa-signed-STAGING' || 'datewise-ios-ipa-signed' }}"));
    });

    test('the built binary is checked for the right coach host', () {
      expect(build, contains("find build/ios/archive -path '*App.framework/App'"));
      expect(build, contains('grep -a -q "datewise-coach-staging.scubamike124.workers.dev" "\$APP_BIN"'));
      expect(build, contains('            if grep -a -q "datewise-coach-staging" "\$APP_BIN"; then'));
      expect(RegExp(r'^\s*! ', multiLine: true).hasMatch(build), isFalse, reason: 'a bare negated command does not trip bash -e');
    });

    test('the host check is symmetric: production must carry the production host', () {
      final appUrl = RegExp(r"productionUrl = '([^']+)'").firstMatch(File('lib/services/ai_config.dart').readAsStringSync())![1]!;
      expect(appUrl, 'https://datewise-photo-coach.scubamike124.workers.dev');
      expect(build, contains('if ! grep -a -q "${Uri.parse(appUrl).host}" "\$APP_BIN"; then'));
      expect(build, contains('A production build does not contain the production coach host.'));
      expect(build, contains('if grep -a -q "datewise-coach-staging" "\$APP_BIN"; then'));
    });

    test('concurrency: staging, production and unsigned runs never cancel each other', () {
      final group = RegExp(r'^  group: (.*)$', multiLine: true).firstMatch(s)![1]!;
      expect(group, contains(r'${{ github.ref }}'));
      expect(group, contains("inputs.signed_build && 'signed' || 'unsigned'"));
      expect(group, contains("inputs.coach_backend || 'production'"));
      expect(group, contains("inputs.signing || 'manual'"));
      expect(group, contains("inputs.avatar_audio_path && 'audio' || 'tts'"));
    });

    test('both signing steps validate APPLE_TEAM_ID before it reaches sed or a plist', () {
      for (final step in ['- name: Manual signing for the Runner target', '- name: Cloud signing for the Runner target']) {
        final at = s.indexOf(step);
        expect(at, greaterThan(-1), reason: step);
        final body = s.substring(at, s.indexOf('\n      - name:', at + 1));
        final check = body.indexOf(r'=~ ^[A-Z0-9]{10}$');
        expect(check, greaterThan(-1), reason: step);
        expect(check, lessThan(body.indexOf("sed -i ''")), reason: step);
      }
    });

    test('runbook: version decision before the build, iOS 18 paths, owner-only merge and deploy', () {
      final runbook = File('docs/qa/IPHONE_E2E_DEMO.md').readAsStringSync();
      final warning = runbook.indexOf('upload the App Store build of a version before any 50000+ build of that version');
      expect(warning, greaterThan(-1));
      expect(warning, lessThan(runbook.indexOf('## 3. Build the TestFlight staging build')));
      // The version is decided before the merge, and the merge is the gate for everything after it.
      expect(warning, lessThan(runbook.indexOf('### 2.4 Merge to `main`')));
      expect(runbook, contains('needs a `pubspec.yaml` change in a reviewed PR before the merge'));
      expect(runbook, contains('**Blocked until you decide to merge.**'));
      // The deploy prerequisites include the mandatory main ruleset, done before the merge.
      expect(runbook, contains('WORKER_DEPLOY_RUNBOOK.md sections 1b to 1f'));
      final protectMain = runbook.indexOf('Do 1f (**Protect `main`**, mandatory) **before** the merge');
      expect(protectMain, greaterThan(-1));
      expect(protectMain, lessThan(runbook.indexOf('1. Merge `claude/datewise-v2-app`')));
      expect(runbook, contains('every push to `main` runs **Deploy to GitHub Pages**'));
      expect(runbook, contains('`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` or `ID_HASH_SALT` is a repository secret'));
      expect(runbook, contains('**Signed IPA / TestFlight (manual, needs secrets)**'));
      expect(runbook, contains('**Settings**, then **Apps**, then **App Store** (iOS 18 and later'));
      expect(runbook, contains('**Settings**, then **Apps**, then **DateWise AI** (iOS 18 and later'));
      expect(runbook, contains("**Merging to `main` and every deploy are the owner's decision alone.**"));
    });

    test('staging without signed_build fails; the unsigned build stays production', () {
      expect(unsigned, contains("if: github.event_name == 'workflow_dispatch' && inputs.coach_backend == 'staging' && !inputs.signed_build"));
      expect(unsigned, contains('run: flutter build ios --release --no-codesign\n'));
      expect(unsigned, isNot(contains('COACH_BACKEND_URL')));
    });

    test('the runbook and checklist document the scheme', () {
      final runbook = File('docs/qa/IPHONE_E2E_DEMO.md').readAsStringSync();
      expect(runbook, contains('coach_backend'));
      expect(runbook, contains('50000'));
      expect(runbook, contains(stagingUrl));
      // iPhone-only, with the pre-live isolation check and the bindings it lists.
      expect(runbook, contains('iPhone only: no Mac needed'));
      expect(runbook, contains('## 1. Pre-live isolation check'));
      for (final id in ['740219', '740220', '740221']) {
        expect(runbook, contains(id));
      }
      final toml = File('backend/wrangler.toml').readAsStringSync();
      final staging = toml.substring(toml.indexOf('[env.staging]'));
      expect(RegExp(r'^namespace_id = "740221"', multiLine: true).hasMatch(staging), isTrue);
      expect(RegExp(r'^\[+env\.staging\.(kv_namespaces|d1_databases|r2_buckets|services|queues|tail_consumers)', multiLine: true).hasMatch(staging), isFalse);
      expect(RegExp(r'^script_name', multiLine: true).hasMatch(staging), isFalse);
      expect(File('docs/appstore/checklist.md').readAsStringSync(), contains('IPHONE_E2E_DEMO.md'));
      expect(File('docs/qa/LIVE_AI_TEST_PLAN.md').readAsStringSync(), contains('IPHONE_E2E_DEMO.md'));
    });
  });

  group('ios-build.yml: Mac-free cloud-managed signing', () {
    final s = File('.github/workflows/ios-build.yml').readAsStringSync();
    final unsigned = s.substring(s.indexOf('  unsigned:'), s.indexOf('  signed-testflight:'));
    final job = s.substring(s.indexOf('  signed-testflight:'));
    String step(String name) {
      final start = job.indexOf('- name: $name');
      expect(start, greaterThan(-1), reason: name);
      final next = job.indexOf(RegExp(r'\n      - (name|uses):'), start + 1);
      return job.substring(start, next < 0 ? job.length : next);
    }

    test('signing is a choice input, manual by default', () {
      expect(s, contains('      signing:\n'));
      expect(s, contains('        type: choice\n        options:\n          - manual\n          - cloud\n        default: manual\n'));
    });

    test('cloud without signed_build fails in the unsigned job; the unsigned build is unchanged', () {
      expect(unsigned, contains("if: github.event_name == 'workflow_dispatch' && inputs.signing == 'cloud' && !inputs.signed_build"));
      expect(unsigned, contains('run: flutter build ios --release --no-codesign\n'));
      expect(unsigned, isNot(contains('secrets.')));
      expect(unsigned, isNot(contains('authenticationKey')));
    });

    test('the secrets check needs only the API key and team for cloud', () {
      final check = step('Check signing secrets');
      expect(check, contains(r'SIGNING: ${{ inputs.signing }}'));
      expect(check, contains('cloud) needed="APPLE_TEAM_ID APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_API_KEY_P8" ;;'));
      expect(check, contains('manual|"") needed="IOS_DIST_CERT_P12_BASE64 IOS_DIST_CERT_PASSWORD IOS_PROVISIONING_PROFILE_BASE64 APPLE_TEAM_ID'));
      expect(check, contains('*) echo "::error::Unknown signing mode"; exit 1 ;;'));
    });

    test('manual steps are skipped for cloud; cloud steps run only for cloud', () {
      for (final name in ['Install certificate and provisioning profile', 'Manual signing for the Runner target']) {
        expect(step(name), contains("if: steps.secrets.outputs.ready == 'true' && inputs.signing != 'cloud'\n"), reason: name);
      }
      for (final name in ['Cloud signing for the Runner target', 'Export and sign the IPA with cloud-managed signing']) {
        expect(step(name), contains("if: steps.secrets.outputs.ready == 'true' && inputs.signing == 'cloud'\n"), reason: name);
      }
      expect(step('Cloud signing for the Runner target'), isNot(contains('IOS_')));
      expect(step('Export and sign the IPA with cloud-managed signing'), isNot(contains('IOS_')));
    });

    test('cloud: automatic signing at build time, app-store-connect export, build number kept', () {
      final cloud = step('Cloud signing for the Runner target');
      expect(cloud, contains(r'APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}'));
      expect(cloud, contains(r'[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]'));
      expect(cloud, contains(r'PRODUCT_BUNDLE_IDENTIFIER = com.datewise.datewiseAi; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = $APPLE_TEAM_ID;/'));
      expect(cloud, contains('<key>method</key><string>app-store-connect</string>'));
      expect(cloud, contains('<key>signingStyle</key><string>automatic</string>'));
      expect(cloud, contains('<key>manageAppVersionAndBuildNumber</key><false/>'));
      expect(cloud, isNot(contains('provisioningProfiles')));
      // The project file in the repository keeps its defaults.
      expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(), isNot(contains('DEVELOPMENT_TEAM')));
      final build = step('flutter build ipa');
      expect(build, contains(r'SIGNING: ${{ inputs.signing }}'));
      expect(build, contains('SIGN_ARGS=(--no-codesign)'));
      expect(build, contains(r'SIGN_ARGS=(--export-options-plist="$RUNNER_TEMP/ExportOptions.plist")'));
      expect(build, contains(r'"${SIGN_ARGS[@]}"'));
    });

    test('cloud export: API key flags, .p8 in RUNNER_TEMP with umask 077, never printed, signature checked', () {
      final export = step('Export and sign the IPA with cloud-managed signing');
      for (final flag in ['-allowProvisioningUpdates', r'-authenticationKeyPath "$RUNNER_TEMP/asc/AuthKey_${ASC_KEY_ID}.p8"', r'-authenticationKeyID "$ASC_KEY_ID"', r'-authenticationKeyIssuerID "$ASC_ISSUER_ID"', '-archivePath build/ios/archive/Runner.xcarchive', '-exportPath build/ios/ipa']) {
        expect(export, contains(flag));
      }
      expect(export, contains('xcodebuild -exportArchive'));
      expect(export, contains('umask 077'));
      expect(export.indexOf('umask 077'), lessThan(export.indexOf(r'> "$RUNNER_TEMP/asc/AuthKey_')));
      expect(export, contains(r'[[ "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]'));
      for (final line in export.split('\n').where((l) => l.contains('ASC_KEY_P8'))) {
        final t = line.trim();
        expect(t.startsWith('ASC_KEY_P8: \${{ secrets.') || t.startsWith(r"printf '%s\n' " '"\$ASC_KEY_P8" >'), isTrue, reason: line);
      }
      expect(export, isNot(contains('cat ')));
      expect(export, contains("grep -q '^Authority=Apple Distribution'"));
      expect(export, contains(r'= "$BUILD_NUMBER"'));
      // Removed by the always() cleanup too.
      final cleanup = job.substring(job.indexOf('- name: Clean up signing material'));
      expect(cleanup, contains(r'"$RUNNER_TEMP/asc"'));
      expect(job.indexOf('- name: Clean up signing material'), greaterThan(job.indexOf('- name: Export and sign the IPA')));
    });

    test('the export runs after the binary host check and before the artifact and upload', () {
      final i = job.indexOf('- name: Export and sign the IPA');
      expect(i, greaterThan(job.indexOf('Coach host check passed')));
      expect(i, lessThan(job.indexOf('- uses: actions/upload-artifact')));
      expect(i, lessThan(job.indexOf('- name: Upload to App Store Connect (TestFlight)')));
    });

    test('the runbook documents the iPhone-only cloud path and the Admin key risk', () {
      final runbook = File('docs/qa/IPHONE_E2E_DEMO.md').readAsStringSync();
      for (final t in ['`signing`', '**`cloud`**', 'Admin', 'Team Keys', 'Generate API Key', 'only once', 'Files', 'Secrets and variables', 'Revoke']) {
        expect(runbook, contains(t), reason: t);
      }
    });
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

    test('the deploy step pins CLOUDFLARE_ENV: empty for production, staging only for chat-v7-staging', () {
      final step = deployJob.substring(deployJob.indexOf('- name: Deploy with Wrangler'), deployJob.indexOf('- name: Remove the salt file'));
      expect(step, contains("        env:\n"));
      expect(step, contains("          CLOUDFLARE_ENV: \${{ needs.check.outputs.target == 'chat-v7-staging' && 'staging' || '' }}\n"));
      expect('CLOUDFLARE_ENV:'.allMatches(s).length, 1, reason: 'set nowhere else');
    });
  });
}
