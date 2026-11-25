import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_config.dart';

/// Owner-only premium access (docs/OWNER_ACCESS.md). The owner enters a code in the hidden Store status sheet;
/// the coach Worker returns a signed 30-day token bound to a random device id. The token is sent as
/// `X-DateWise-Owner`; the Worker treats it as a premium entitlement with the normal limits. It is not a
/// purchase and changes nothing for customers. The token is never logged or shown.
class OwnerAccess extends ChangeNotifier {
  OwnerAccess._();
  static final OwnerAccess instance = OwnerAccess._();

  /// Compiled in only for internal TestFlight builds (`--dart-define=DW_OWNER_ACCESS=true`). Public builds leave
  /// it false: the feature is inert and its button is not shown (Apple 3.1.1 / 2.3.1; docs/OWNER_ACCESS.md).
  static const bool enabled = bool.fromEnvironment('DW_OWNER_ACCESS');

  static const _kToken = 'owner_token_v1';
  static const _kDevice = 'owner_device_v1';
  static const _renewBefore = Duration(days: 10);

  /// Keychain (iOS) / Keystore (Android) storage. Tests replace it with [useStore].
  static OwnerStore _store = KeychainOwnerStore();

  /// Test seam: swap the storage backend.
  @visibleForTesting
  static void useStore(OwnerStore s) => _store = s;

  String? _token;
  DateTime? _expires;

  /// The token to send, or null (none, or expired on this device, or the feature is compiled out).
  static String? get token => instance.active ? instance._token : null;

  bool get active => enabled && _token != null && _expires != null && _expires!.isAfter(DateTime.now());

  /// Reads a saved token at launch and renews it when it is close to the end. Also moves a token saved by an
  /// earlier build (SharedPreferences) into the Keychain.
  Future<void> load({String? baseUrl, http.Client? client}) async {
    if (!enabled) {
      // Public builds never use owner access, but a token left by an earlier internal build is removed.
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove(_kToken);
        await p.remove(_kDevice);
        await _store.delete(_kToken);
      } catch (_) {}
      return;
    }
    try {
      await _migrate();
      _token = await _store.read(_kToken);
      _expires = _parseExpiry(_token);
      if (!active) _token = null;
      notifyListeners();
      if (active && _expires!.difference(DateTime.now()) < _renewBefore) {
        await _call('/owner/renew', {'token': _token}, baseUrl: baseUrl, client: client);
      }
    } catch (_) {
      /* owner access is optional; never block launch */
    }
  }

  /// Redeems [code]. Returns true when the Worker accepted it.
  Future<bool> redeem(String code, {String? baseUrl, http.Client? client}) async {
    if (!enabled) return false;
    try {
      var dev = await _store.read(_kDevice);
      if (dev == null) {
        final r = Random.secure();
        dev = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        await _store.write(_kDevice, dev);
      }
      return await _call('/owner/redeem', {'code': code.trim(), 'deviceId': dev}, baseUrl: baseUrl, client: client);
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    _token = null;
    _expires = null;
    try {
      await _store.delete(_kToken);
    } catch (_) {}
    notifyListeners();
  }

  /// One-time move of the earlier SharedPreferences copy into the Keychain, then the old copy is removed.
  Future<void> _migrate() async {
    final p = await SharedPreferences.getInstance();
    final old = p.getString(_kToken);
    if (old != null) {
      // Never overwrite a newer token already in the Keychain; the old copy is only removed.
      if (await _store.read(_kToken) == null) await _store.write(_kToken, old);
      await p.remove(_kToken);
    }
    final oldDev = p.getString(_kDevice);
    if (oldDev != null) {
      if (await _store.read(_kDevice) == null) await _store.write(_kDevice, oldDev);
      await p.remove(_kDevice);
    }
  }

  Future<bool> _call(String path, Map<String, Object?> body, {String? baseUrl, http.Client? client}) async {
    final base = Uri.parse(baseUrl ?? AIConfig.coachBackendUrl.trim());
    if (base.scheme != 'https') return false;
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(base.replace(path: path, query: ''), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      final t = (jsonDecode(res.body) as Map)['token'];
      if (t is! String || _parseExpiry(t) == null) return false;
      _token = t;
      _expires = _parseExpiry(t);
      await _store.write(_kToken, t);
      notifyListeners();
      return true;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Token format `o1.<device>.<expSeconds>.<sig>`; the Worker is the one that verifies it.
  static DateTime? _parseExpiry(String? t) {
    final parts = t?.split('.');
    final s = parts != null && parts.length == 4 && parts[0] == 'o1' ? int.tryParse(parts[2]) : null;
    return s == null ? null : DateTime.fromMillisecondsSinceEpoch(s * 1000);
  }
}

/// Storage seam: the Keychain in the app, memory in tests.
abstract class OwnerStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeychainOwnerStore implements OwnerStore {
  // Readable only after the first unlock on this device; never synced to iCloud Keychain.
  static const _s = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}
