import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../../services/ai_config.dart';
import '../../services/coach_usage.dart';

/// A short-lived vendor session handed out by the Worker (POST /v1/avatar/session).
/// It holds the vendor's session token only; the vendor API key never leaves the Worker.
class AvatarSession {
  const AvatarSession({
    required this.sessionId,
    required this.vendor,
    required this.sessionToken,
    required this.maxSeconds,
    required this.idleSeconds,
    required this.heartbeatSeconds,
    required this.sampleRate,
    required this.usedSeconds,
    required this.totalSeconds,
  });

  final String sessionId;
  final String vendor;
  final String sessionToken;
  final int maxSeconds;
  final int idleSeconds;
  final int heartbeatSeconds;
  final int sampleRate;
  final int usedSeconds;
  final int totalSeconds;

  static AvatarSession? parse(Object? json) {
    if (json is! Map) return null;
    final audio = json['audio'];
    final allowance = json['allowance'];
    final id = json['sessionId'], vendor = json['vendor'], token = json['sessionToken'];
    if (id is! String || vendor is! String || token is! String || token.isEmpty) return null;
    int n(Object? v, int d) => v is num ? v.toInt() : d;
    return AvatarSession(
      sessionId: id,
      vendor: vendor,
      sessionToken: token,
      maxSeconds: n(json['maxSeconds'], 0),
      idleSeconds: n(json['idleSeconds'], 60),
      heartbeatSeconds: n(json['heartbeatSeconds'], 30).clamp(5, 120),
      sampleRate: audio is Map ? n(audio['sampleRate'], 16000) : 16000,
      usedSeconds: allowance is Map ? n(allowance['usedSeconds'], 0) : 0,
      totalSeconds: allowance is Map ? n(allowance['totalSeconds'], 0) : 0,
    );
  }
}

/// Why the Worker said no (stable codes of backend/avatar.js and cost_guard.js).
class AvatarRefusal implements Exception {
  const AvatarRefusal(this.code, {this.statusCode, this.reason});
  final String code;
  final int? statusCode;
  final String? reason;
  @override
  String toString() => 'AvatarRefusal($code, $statusCode)';
}

/// The network could not be reached or timed out.
class AvatarOffline implements Exception {
  const AvatarOffline();
}

/// Thin client for the three avatar endpoints. The entitlement header is the
/// same StoreKit 2 JWS the chat sends (EntitlementToken); no other credential.
class AvatarSessionApi {
  AvatarSessionApi({String? baseUrl, http.Client Function()? clientFactory, String? Function()? entitlement, this.timeout = const Duration(seconds: 10)})
      : _base = (baseUrl ?? AIConfig.coachBackendUrl).replaceAll(RegExp(r'/+$'), ''),
        _clientFactory = clientFactory ?? http.Client.new,
        _entitlement = entitlement ?? (() => EntitlementToken.current);

  final String _base;
  final http.Client Function() _clientFactory;
  final String? Function() _entitlement;
  final Duration timeout;

  Future<AvatarSession> open({required String coachId, String? language}) async {
    final body = await _post('session', {'coachId': coachId, if (language != null) 'language': language});
    final s = AvatarSession.parse(body);
    if (s == null) throw const AvatarRefusal('AVATAR_UNAVAILABLE', reason: 'bad_response');
    return s;
  }

  /// Returns the seconds used this month, when the Worker says.
  Future<int?> heartbeat(String sessionId) async {
    final body = await _post('heartbeat', {'sessionId': sessionId});
    final used = body is Map ? body['usedSeconds'] : null;
    return used is num ? used.toInt() : null;
  }

  Future<int?> end(String sessionId) async {
    final body = await _post('end', {'sessionId': sessionId});
    final used = body is Map ? body['usedSeconds'] : null;
    return used is num ? used.toInt() : null;
  }

  Future<Object?> _post(String action, Map<String, Object?> body) async {
    final jws = _entitlement();
    if (jws == null) throw const AvatarRefusal('SUBSCRIPTION_REQUIRED');
    final client = _clientFactory();
    try {
      final res = await client
          .post(
            Uri.parse('$_base/v1/avatar/$action'),
            headers: {'Content-Type': 'application/json', 'X-DateWise-Entitlement': jws},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      Object? json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        json = null;
      }
      if (res.statusCode != 200) {
        final code = json is Map && json['code'] is String ? json['code'] as String : 'HTTP_${res.statusCode}';
        throw AvatarRefusal(code, statusCode: res.statusCode, reason: json is Map ? json['reason'] as String? : null);
      }
      return json;
    } on TimeoutException {
      throw const AvatarOffline();
    } on SocketException {
      throw const AvatarOffline();
    } on http.ClientException {
      throw const AvatarOffline();
    } finally {
      client.close();
    }
  }
}
