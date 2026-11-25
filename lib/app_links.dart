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

  // --- "Find a table" / "Plan a table" (lib/widgets/plan_table_sheet.dart) --
  // Search links only: DateWise has no partner API, account or booking. Each
  // link carries only what the user typed into the planner, never chat
  // content, and opens outside the app only when tapped. DateWise asks for no
  // location permission: the map apps use their own location setting.

  /// Apple Maps search (iPhone, iPad, Mac): `https://maps.apple.com/?q=QUERY`.
  static Uri findTableUri(String query) =>
      Uri.parse('https://maps.apple.com/?q=${Uri.encodeComponent(query.trim())}');

  /// Google Maps search URL, as documented in "Get started with Maps URLs"
  /// (developers.google.com/maps/documentation/urls/get-started, checked
  /// 2026-11-25): `https://www.google.com/maps/search/?api=1&query=QUERY`,
  /// URL-encoded, no API key, opens the Google Maps app or the website.
  static Uri googleMapsSearchUri(String query) =>
      Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query.trim())}');

  /// OpenTable restaurant search for a party size, local date and time, and
  /// an optional free-text term (cuisine and area), e.g.
  /// https://www.opentable.com/s/?covers=4&dateTime=2026-11-28T19%3A30%3A00&term=Italian%20Chicago
  /// OpenTable's own pages show live availability and the user books there.
  ///
  /// NOT VERIFIED against OpenTable documentation: OpenTable publishes no
  /// public spec for its search URL, and its site refused automated requests
  /// (403/503) on 2026-11-25. The parameters (`covers` = party size,
  /// `dateTime` = local ISO 8601 with seconds and no zone, `term` = free text)
  /// follow the search URLs OpenTable's site produces, as recorded by several
  /// independent third-party integrations. No price filter is sent: none could
  /// be verified, so the budget goes only into the map searches.
  /// Re-check on a device before release; if OpenTable ignores a parameter,
  /// the page still opens its own search, so the user is never misled.
  static Uri openTableSearchUri({required int covers, required DateTime dateTime, String term = ''}) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dateTime;
    final iso = '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}:00';
    final t = term.trim();
    return Uri.parse('https://www.opentable.com/s/?covers=$covers&dateTime=${Uri.encodeComponent(iso)}'
        '${t.isEmpty ? '' : '&term=${Uri.encodeComponent(t)}'}');
  }
}
