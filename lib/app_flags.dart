/// App-wide feature flags.
class AppFlags {
  AppFlags._();

  /// MASTER SWITCH for the free launch.
  ///
  /// When `true`: every capability is unlocked for every user and all
  /// pricing / paywall UI is hidden — the app ships as fully free.
  ///
  /// To monetise later, set this to `false` (which restores the tier gates,
  /// the Plans tab, and the web pricing section) and replace
  /// `MockPurchaseService` with real billing behind the existing
  /// `PurchaseService` seam. No tier or pricing code was removed.
  static const bool freeLaunch = true;

  /// The AI Photo Coach is available on every tier. Implied by [freeLaunch]
  /// (kept as a named alias so existing references keep compiling).
  static const bool unlockPhotoCoachForTesting = freeLaunch;
}
