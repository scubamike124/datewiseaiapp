import 'package:shared_preferences/shared_preferences.dart';

/// The second AI-sharing consent: before the first live session the user is
/// asked, once, to let DateWise send the coach's spoken reply and portrait to
/// the avatar vendor (App Store Guideline 5.1.2(i)). The vendor is named in the
/// dialog, so consent is stored per vendor and asked again if the vendor changes.
///
/// Stored under a `dw_` key, so "Delete my data" (StorageService.clearAll)
/// removes it. [withdraw] removes only this permission. Nothing is sent to the
/// vendor unless [has] is true (HostedAvatarController checks it first).
class AvatarConsent {
  AvatarConsent(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'dw_avatar_consent';
  static const version = 1;

  bool has(String vendor) => _prefs.getString(_key) == '$version:${vendor.toLowerCase()}';
  Future<void> grant(String vendor) => _prefs.setString(_key, '$version:${vendor.toLowerCase()}');
  Future<void> withdraw() => _prefs.remove(_key);
}
