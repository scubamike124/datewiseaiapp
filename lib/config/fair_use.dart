/// DateWise Premium's fair-use limits, as the coach backend enforces them
/// (backend/wrangler.toml [vars]). The single source for every disclosure:
/// the paywall line, the Terms of Use and (by hand, checked by a test) the
/// App Store description. test/fair_use_test.dart fails when these differ
/// from wrangler.toml, so the disclosure cannot drift from the server.
///
/// Typed and spoken messages count the same: each coach reply is one.
/// Pure Dart (no Flutter import): tool/legal_pages.dart uses it too.
library;

class FairUse {
  FairUse._();

  /// Coach replies per subscriber per UTC day (DAILY_MESSAGE_LIMIT).
  static const int dailyReplies = 150;

  /// Coach replies per subscriber per calendar month, UTC (MONTHLY_MESSAGE_LIMIT).
  static const int monthlyReplies = 1500;

  /// Coach replies per subscriber per minute (PER_MINUTE_LIMIT).
  static const int perMinute = 12;

  /// Replies being written at the same time per subscriber (MAX_CONCURRENT).
  static const int concurrent = 2;

  /// The notice appears from this share of the daily or monthly limit
  /// (SOFT_NOTICE_PERCENT).
  static const int noticePercent = 80;

  /// [n] with a thousands separator: "1,500" in English. Spanish writes
  /// four-digit numbers without one ("1500", RAE) and groups larger ones
  /// with a space ("15 000").
  static String format(int n, String languageCode) {
    final digits = n.abs().toString();
    final spanish = languageCode.startsWith('es');
    if (spanish && digits.length <= 4) return n.toString();
    final sep = spanish ? ' ' : ',';
    final out = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(sep);
      out.write(digits[i]);
    }
    return out.toString();
  }
}
