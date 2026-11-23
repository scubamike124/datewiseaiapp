/// External links and contact details surfaced in Settings and on the legal
/// screens. These are the live values for the published app.
class AppLinks {
  AppLinks._();

  /// Support / contact email (used by "Contact support" → mail composer).
  static const String supportEmail = 'support@datewiseai.com';

  /// Public Privacy Policy / Terms URLs on datewiseai.com. They serve
  /// web/privacy.html and web/terms.html (generated from
  /// lib/content/legal_text.dart by tool/legal_pages.dart) through the clean-URL
  /// rules in web/_redirects (Netlify) and web/.htaccess (Apache). The in-app
  /// legal screens also offer a "View online" link to them.
  static const String privacyPolicyUrl = 'https://datewiseai.com/privacy-policy';
  static const String termsUrl = 'https://datewiseai.com/terms-of-service';

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
}
