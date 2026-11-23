import '../l10n/app_localizations.dart';
import 'coach_usage.dart';

/// The localized chat notice for a coach backend refusal code (see
/// [CoachLimitCode]), or null when the code is unknown or absent (the chat
/// then shows its generic "try again" notice).
String? coachLimitMessage(AppLocalizations l, String? code) => switch (code) {
      CoachLimitCode.dailyLimit => l.coachLimitDaily,
      CoachLimitCode.monthlyLimit => l.coachLimitMonthly,
      CoachLimitCode.rateLimited || CoachLimitCode.concurrencyLimit => l.coachLimitSlowDown,
      CoachLimitCode.serviceBudgetExhausted || CoachLimitCode.guardUnavailable => l.coachLimitBusy,
      CoachLimitCode.subscriptionExpired || CoachLimitCode.subscriptionRequired => l.coachLimitSubscriptionInactive,
      CoachLimitCode.subscriptionRevoked => l.coachLimitRevoked,
      CoachLimitCode.subscriptionInvalid => l.coachLimitVerify,
      CoachLimitCode.appUpdateRequired => l.coachLimitUpdateApp,
      _ => null,
    };

/// The localized soft notice for the `X-DateWise-Usage-Notice` value, or null.
String? coachUsageNotice(AppLocalizations l, String? notice) => switch (notice) {
      'approaching_daily_limit' => l.coachUsageNoticeDaily,
      'approaching_monthly_limit' => l.coachUsageNoticeMonthly,
      _ => null,
    };
