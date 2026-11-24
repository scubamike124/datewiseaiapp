/// External links and contact details surfaced in Settings and on the legal
/// screens. These are the live values for the published app.
class AppLinks {
  AppLinks._();

  /// Support / contact email (used by "Contact support" → mail composer).
  static const String supportEmail = 'support@datewiseai.com';

  /// Public Privacy Policy / Terms URLs, published by the owner on Lovable
  /// (owner decision, 2026-11-24). They serve web/privacy.html and
  /// web/terms.html (generated from lib/content/legal_text.dart by
  /// tool/legal_pages.dart); the Spanish pages are at /privacy-es.html and
  /// /terms-es.html on the same host. web/_redirects and web/.htaccess keep the
  /// same clean paths for any other host. These URLs are also the App Store
  /// Connect Privacy Policy and Support URLs.
  static const String privacyPolicyUrl = 'https://datewise-legal.lovable.app/privacy-policy';
  static const String termsUrl = 'https://datewise-legal.lovable.app/terms-of-service';

  /// Customer support page: the App Store Connect Support URL. It serves
  /// web/support.html (generated from lib/content/support_text.dart by
  /// tool/legal_pages.dart; Spanish at /support-es.html), published by the
  /// owner on the same Lovable site as the legal pages.
  static const String supportUrl = 'https://datewise-legal.lovable.app/support.html';

  /// Android Play Store listing (for "Rate the app"). Matches the release
  /// `applicationId` in android/app/build.gradle.kts.
  static const String androidPackage = 'com.datewise.ai';
  static String get playStoreUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackage';

  /// Apple App Store numeric id (App Store Connect → App Information →
  /// "Apple ID"). Live listing: DateWise AI - Dating Coach.
  static const String iosAppStoreId = '6780110141';
  static String get appStoreUrl => 'https://apps.apple.com/app/id$iosAppStoreId';

  /// Play "manage subscriptions" page.
  static const String manageSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions';

  /// "Find a table" on first-date plans: an Apple Maps search, opened only
  /// when the user taps it. [query] is a generic search ("restaurants"), never
  /// chat content. Apple Maps searches near the phone with its own location
  /// setting, so DateWise asks for no location permission.
  static Uri findTableUri(String query) =>
      Uri.parse('https://maps.apple.com/?q=${Uri.encodeComponent(query.trim())}');
}
