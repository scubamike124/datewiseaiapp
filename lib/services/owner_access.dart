import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
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

  static const _kToken = 'owner_token_v1';
  static const _kDevice = 'owner_device_v1';
  static const _renewBefore = Duration(days: 10);

  String? _token;
  DateTime? _expires;

  /// The token to send, or null (none, or expired on this device).
  static String? get token => instance.active ? instance._token : null;

  bool get active => _token != null && _expires != null && _expires!.isAfter(DateTime.now());

  /// Reads a saved token at launch and renews it when it is close to the end.
  Future<void> load({String? baseUrl, http.Client? client}) async {
    try {
      final p = await SharedPreferences.getInstance();
      _token = p.getString(_kToken);
      _expires = _parseExpiry(_token);
      if (!active) _token = null;
      notifyListeners();
      if (active && _expires!.difference(DateTime.now()) < _renewBefore) {
        await _call('/owner/renew', {'token': _token}, p, baseUrl: baseUrl, client: client);
      }
    } catch (_) {
      /* owner access is optional; never block launch */
    }
  }

  /// Redeems [code]. Returns true when the Worker accepted it.
  Future<bool> redeem(String code, {String? baseUrl, http.Client? client}) async {
    try {
      final p = await SharedPreferences.getInstance();
      var dev = p.getString(_kDevice);
      if (dev == null) {
        final r = Random.secure();
        dev = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        await p.setString(_kDevice, dev);
      }
      return await _call('/owner/redeem', {'code': code.trim(), 'deviceId': dev}, p, baseUrl: baseUrl, client: client);
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    _token = null;
    _expires = null;
    try {
      (await SharedPreferences.getInstance()).remove(_kToken);
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> _call(String path, Map<String, Object?> body, SharedPreferences p, {String? baseUrl, http.Client? client}) async {
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
      await p.setString(_kToken, t);
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
