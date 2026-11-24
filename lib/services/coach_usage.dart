import 'package:flutter/foundation.dart';

/// The App Store-signed StoreKit 2 transaction (its JWS) for the active
/// DateWise Premium subscription. The coach backend (chat-v7) verifies it
/// offline against Apple's root certificate and keys fair-use counters on a
/// hash of its originalTransactionId. No account is involved, and the app
/// never stores counters: the server's are the only ones that count.
///
/// Set by [AppStoreService] whenever it reads the current entitlements;
/// null when there is no active subscription (or off iOS).
class EntitlementToken {
  EntitlementToken._();

  static String? _jws;

  /// The JWS to send as `X-DateWise-Entitlement`, or null.
  static String? get current => _jws;

  static void update(String? jws) => _jws = (jws == null || jws.isEmpty) ? null : jws;

  /// Re-reads the current entitlement from StoreKit (set by the store). The
  /// chat calls it once when the backend says the token is expired or invalid,
  /// then retries, because a renewal may not have reached the token yet.
  static Future<void> Function()? refresher;

  /// Keeps [data] only when it is a compact JWS (StoreKit 2). A StoreKit 1
  /// receipt or a Google Play token is ignored and leaves the token unchanged.
  static void updateIfJws(String? data) {
    if (data != null && RegExp(r'^[\w-]+\.[\w-]+\.[\w-]+$').hasMatch(data)) _jws = data;
  }
}

/// Error codes the coach backend (chat-v7) returns in `{"code": …}` when it
/// refuses a request. The chat maps each to a localized message.
class CoachLimitCode {
  CoachLimitCode._();
  static const dailyLimit = 'DAILY_LIMIT';
  static const monthlyLimit = 'MONTHLY_LIMIT';
  static const rateLimited = 'RATE_LIMITED';
  static const concurrencyLimit = 'CONCURRENCY_LIMIT';
  static const serviceBudgetExhausted = 'SERVICE_BUDGET_EXHAUSTED';
  static const guardUnavailable = 'GUARD_UNAVAILABLE';
  static const subscriptionRequired = 'SUBSCRIPTION_REQUIRED';
  static const subscriptionInvalid = 'SUBSCRIPTION_INVALID';
  static const subscriptionExpired = 'SUBSCRIPTION_EXPIRED';
  static const subscriptionRevoked = 'SUBSCRIPTION_REVOKED';
  /// Codes that mean the subscription itself changed (refund, revocation, expiry): the app re-reads the
  /// entitlement when it gets one.
  static const entitlementChanged = {subscriptionRevoked, subscriptionExpired, subscriptionRequired};
  static const appUpdateRequired = 'APP_UPDATE_REQUIRED';

  /// Codes that a fresh StoreKit entitlement may fix (one refresh, one retry).
  static const refreshable = {subscriptionExpired, subscriptionInvalid, subscriptionRequired};

  /// Codes that an immediate retry cannot fix, so the chat offers none:
  /// the daily and monthly caps, a refunded purchase and an outdated app.
  static const noInstantRetry = {dailyLimit, monthlyLimit, subscriptionRevoked, appUpdateRequired};

  /// Codes whose chat notice also offers the paywall (Subscribe and Restore
  /// purchases): the subscription is not active, was refunded or revoked, or
  /// could not be confirmed.
  static const paywallAction = {subscriptionExpired, subscriptionRequired, subscriptionRevoked, subscriptionInvalid};
}

/// The fair-use state reported with the last successful reply.
@immutable
class CoachUsageState {
  const CoachUsageState({this.notice, this.remainingToday, this.remainingMonth});

  /// `approaching_daily_limit`, `approaching_monthly_limit`, or null.
  final String? notice;
  final int? remainingToday;
  final int? remainingMonth;

  /// Reads the chat-v7 response headers (lower-case keys, as package:http gives them).
  static CoachUsageState fromHeaders(Map<String, String> headers) => CoachUsageState(
        notice: headers['x-datewise-usage-notice'],
        remainingToday: int.tryParse(headers['x-datewise-remaining-today'] ?? ''),
        remainingMonth: int.tryParse(headers['x-datewise-remaining-month'] ?? ''),
      );
}

/// Latest usage state, for an optional soft notice in the chat UI.
class CoachUsage {
  CoachUsage._();
  static final ValueNotifier<CoachUsageState?> state = ValueNotifier<CoachUsageState?>(null);
}
