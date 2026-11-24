import 'package:flutter/foundation.dart' show visibleForTesting;

/// Configuration for the AI coach backend.
///
/// The coaches run on a secure backend (a Cloudflare Worker, see
/// `backend/worker.js`) that holds the model access server-side. The app
/// ships **no API keys or secrets**: it only knows the Worker's public HTTPS
/// URL.
///
/// Override the URL at build time if needed (it must be HTTPS):
///   flutter run --dart-define=COACH_BACKEND_URL=https://your-worker.workers.dev
class AIConfig {
  AIConfig._();

  /// Production coach backend (owner Cloudflare account).
  static const String productionUrl = 'https://datewise-photo-coach.scubamike124.workers.dev';

  /// Public URL of the coach Worker (`--dart-define=COACH_BACKEND_URL`, or
  /// the older `PHOTO_COACH_URL`, else [productionUrl]).
  static const String coachBackendUrl = String.fromEnvironment(
    'COACH_BACKEND_URL',
    defaultValue: String.fromEnvironment('PHOTO_COACH_URL', defaultValue: productionUrl),
  );

  /// Only an HTTPS URL is used. Otherwise a debug build falls back to the
  /// offline demo coach and a release build fails every reply (see
  /// AIServiceFactory).
  static bool get hasCoachBackend => isUsableUrl(coachBackendUrl);

  /// Whether [url] can be used as the coach backend (HTTPS only).
  static bool isUsableUrl(String url) => Uri.tryParse(url.trim())?.scheme == 'https';

  /// The coach host to show testers, or null. Only a build pointed at a
  /// backend other than [productionUrl] (the TestFlight staging build of
  /// docs/qa/IPHONE_E2E_DEMO.md) shows it, so App Store builds, which never
  /// set COACH_BACKEND_URL, show nothing. No staging host is written here:
  /// production binaries do not contain it (ios-build.yml checks this).
  static String? testBuildHost([String? url]) {
    url = (url ?? debugUrlForHostLabel ?? coachBackendUrl).trim();
    if (url == productionUrl || !isUsableUrl(url)) return null;
    return Uri.parse(url).host;
  }

  /// Tests only: the URL [testBuildHost] reads instead of the build's.
  @visibleForTesting
  static String? debugUrlForHostLabel;
}
