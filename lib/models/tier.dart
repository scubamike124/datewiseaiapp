/// A field of the coach backend's request protocol, kept for compatibility.
///
/// DateWise has a single product, the DateWise Premium monthly subscription
/// (see `StoreConfig`); there are no plan tiers in the app. The legacy
/// backend still reads a `tier` name, and the full-toolkit one is sent.
enum SubscriptionTier {
  spark,
  flame,
  magnet;

  static SubscriptionTier fromId(String? id) {
    return SubscriptionTier.values.firstWhere(
      (t) => t.name == id,
      orElse: () => SubscriptionTier.magnet,
    );
  }
}
