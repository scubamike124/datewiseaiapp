/// External links and contact details surfaced in Settings.
///
/// Replace these placeholders with your real values before publishing.
class AppLinks {
  AppLinks._();

  /// Support / contact email (used by "Contact support" → mail composer).
  static const String supportEmail = 'support@datewise.app';

  /// Optional public Privacy Policy / Terms URLs. When empty, Settings shows the
  /// in-app pages only; when set, a "View online" link is also offered.
  static const String privacyPolicyUrl = '';
  static const String termsUrl = '';

  /// Android Play Store listing (for "Rate the app"). Matches the release
  /// `applicationId` in android/app/build.gradle.kts.
  static const String androidPackage = 'com.datewise.datewise_ai';
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
