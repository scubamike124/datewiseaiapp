/// External links and contact details surfaced in Settings.
///
/// Replace these placeholders with your real values before publishing.
class AppLinks {
  AppLinks._();

  /// Support / contact email (used by "Contact support" → mail composer).
  static const String supportEmail = 'support@datewiseai.com';

  /// Public Privacy Policy / Terms URLs (hosted on datewiseai.com; also bundled in
  /// the web build as web/privacy.html + web/terms.html). When set, the in-app
  /// legal screens also offer a "View online" link.
  static const String privacyPolicyUrl = 'https://datewiseai.com/privacy-policy';
  static const String termsUrl = 'https://datewiseai.com/terms-of-service';

  /// Android Play Store listing (for "Rate the app"). Matches the release
  /// `applicationId` in android/app/build.gradle.kts.
  static const String androidPackage = 'com.datewise.ai';
  static String get playStoreUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackage';

  /// Apple App Store numeric id (App Store Connect → App Information →
  /// "Apple ID"). Empty until the app is published; when empty, the iOS
  /// "Rate the app" action is hidden so it never opens the wrong store.
  static const String iosAppStoreId = '';
  static String get appStoreUrl => 'https://apps.apple.com/app/id$iosAppStoreId';

  /// Play "manage subscriptions" page.
  static const String manageSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions';
}
