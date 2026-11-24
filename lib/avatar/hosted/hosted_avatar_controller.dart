import 'dart:async';

import 'package:flutter/foundation.dart';

import 'avatar_audio_source.dart';
import 'avatar_bridge.dart';
import 'avatar_consent.dart';
import 'avatar_flags.dart';
import 'avatar_session_api.dart';
import 'bridge_protocol.dart';

enum HostedAvatarState { idle, connecting, live, fallback }

/// Why the stage shows the frame avatar instead of the live face. Every reason
/// is handled the same way, silently (no dialog): the frame avatar and the
/// system voice take over, and the reply text is never affected.
enum FallbackReason {
  flagOff,
  noConsent,
  noEntitlement,
  allowanceExhausted,
  dailyCap,
  busy,
  unavailable, // Worker says off / no key / vendor error
  offline,
  poorNetwork,
  sessionError,
  permissionDenied,
  webViewFailed,
  connectTimeout,
  audioUnavailable,
  sessionEnded, // max length or idle close
  collapsed,
  backgrounded,
}

/// Runs one hosted live-avatar session at a time:
///   flag -> consent -> entitlement -> Worker session -> WebView bridge -> live.
/// Nothing leaves the device before consent. The coach's reply TEXT stays the
/// source of truth: [speakReply] turns exactly that text into audio for the vendor.
class HostedAvatarController extends ChangeNotifier {
  HostedAvatarController({
    required this.api,
    required this.bridge,
    required this.audio,
    required this.consent,
    required this.flags,
    required this.coachId,
    this.language = 'en',
    this.askConsent,
    this.hasEntitlement,
    this.connectTimeout = const Duration(seconds: 15),
    this.heartbeatFailuresAllowed = 2,
    this.poorReportsAllowed = 2,
  });

  final AvatarSessionApi api;
  final AvatarBridge bridge;
  final AvatarAudioSource audio;
  final AvatarConsent consent;
  final AvatarFlags flags;
  final String coachId;
  final String language;

  /// Shows the consent dialog; true when the user agreed. Only called when the
  /// owner-approved copy flag is on. Null: the session cannot start without prior consent.
  final Future<bool> Function()? askConsent;

  /// Whether a StoreKit entitlement exists (checked before any network call).
  final bool Function()? hasEntitlement;
  final Duration connectTimeout;
  final int heartbeatFailuresAllowed;
  final int poorReportsAllowed;

  HostedAvatarState _state = HostedAvatarState.idle;
  FallbackReason? _fallback;
  AvatarActivity _activity = AvatarActivity.idle;
  int? _firstFrameMs;
  int? _rttMs;
  String _mic = 'unknown';
  int? _usedSeconds;
  int? _totalSeconds;
  String? _lastError;
  AvatarSession? _session;
  StreamSubscription<AvatarBridgeEvent>? _sub;
  Timer? _connectTimer, _beatTimer, _maxTimer;
  int _beatFailures = 0, _poorReports = 0;
  int _generation = 0; // guards async continuations of an older start()
  bool _disposed = false;
  bool _firstFrame = false;
  int _speakSeq = 0;

  HostedAvatarState get state => _state;
  FallbackReason? get fallbackReason => _fallback;
  AvatarActivity get activity => _activity;
  int? get firstFrameMs => _firstFrameMs;
  int? get rttMs => _rttMs;
  String get micState => _mic;
  int? get usedSeconds => _usedSeconds;
  int? get totalSeconds => _totalSeconds;
  String? get lastError => _lastError;
  String? get vendor => _session?.vendor;
  bool get isLive => _state == HostedAvatarState.live;
  bool get showsLiveFace => _state == HostedAvatarState.connecting || _state == HostedAvatarState.live;

  void _set({HostedAvatarState? state, FallbackReason? fallback, AvatarActivity? activity}) {
    if (state != null) _state = state;
    if (fallback != null) _fallback = fallback;
    if (activity != null) _activity = activity;
    if (!_disposed) notifyListeners();
  }

  /// Starts a live session, or ends in [HostedAvatarState.fallback] with a reason.
  Future<void> start() async {
    if (_state == HostedAvatarState.connecting || _state == HostedAvatarState.live) return;
    final gen = ++_generation;
    _fallback = null;
    _lastError = null;
    _firstFrame = false;
    _firstFrameMs = null;

    if (!flags.hostedEnabled) return _fail(FallbackReason.flagOff);
    // Consent first: nothing is sent anywhere without it.
    if (!consent.has(flags.vendorName)) {
      var ok = false;
      if (flags.consentCopyApproved && askConsent != null) {
        ok = await askConsent!();
        if (ok) await consent.grant(flags.vendorName);
      }
      if (gen != _generation || _disposed) return;
      if (!ok) return _fail(FallbackReason.noConsent);
    }
    if (hasEntitlement != null && !hasEntitlement!()) return _fail(FallbackReason.noEntitlement);

    _set(state: HostedAvatarState.connecting);
    AvatarSession session;
    try {
      session = await api.open(coachId: coachId, language: language);
    } on AvatarRefusal catch (r) {
      if (gen != _generation) return;
      _lastError = r.code;
      return _fail(_reasonFor(r));
    } on AvatarOffline {
      if (gen != _generation) return;
      return _fail(FallbackReason.offline);
    } catch (_) {
      if (gen != _generation) return;
      return _fail(FallbackReason.sessionError);
    }
    if (gen != _generation || _disposed) {
      // Stopped while the Worker call was in flight: give the minutes back.
      unawaited(api.end(session.sessionId).then<void>((_) {}, onError: (Object _) {}));
      return;
    }
    _session = session;
    _usedSeconds = session.usedSeconds;
    _totalSeconds = session.totalSeconds;
    _sub = bridge.events.listen(_onEvent);
    _connectTimer = Timer(connectTimeout, () {
      if (!_firstFrame) _fail(FallbackReason.connectTimeout);
    });
    await bridge.send(StartCommand(
      vendor: session.vendor,
      sessionToken: session.sessionToken,
      sampleRate: session.sampleRate,
      idleSeconds: session.idleSeconds,
      maxSeconds: session.maxSeconds,
    ));
    _beatTimer = Timer.periodic(Duration(seconds: session.heartbeatSeconds), (_) => _beat(gen));
    if (session.maxSeconds > 0) {
      _maxTimer = Timer(Duration(seconds: session.maxSeconds), () => _fail(FallbackReason.sessionEnded));
    }
  }

  FallbackReason _reasonFor(AvatarRefusal r) => switch (r.code) {
        'SUBSCRIPTION_REQUIRED' || 'SUBSCRIPTION_INVALID' || 'SUBSCRIPTION_EXPIRED' || 'SUBSCRIPTION_REVOKED' => FallbackReason.noEntitlement,
        'AVATAR_ALLOWANCE' => FallbackReason.allowanceExhausted,
        'AVATAR_DAILY_CAP' => FallbackReason.dailyCap,
        'AVATAR_BUSY' => FallbackReason.busy,
        'AVATAR_UNAVAILABLE' || 'GUARD_UNAVAILABLE' || 'SERVICE_BUDGET_EXHAUSTED' => FallbackReason.unavailable,
        _ => FallbackReason.sessionError,
      };

  void _onEvent(AvatarBridgeEvent e) {
    switch (e) {
      case ReadyEvent():
        break;
      case StateEvent(:final activity):
        _set(activity: activity);
      case FirstFrameEvent(:final ms):
        _firstFrame = true;
        _connectTimer?.cancel();
        _firstFrameMs = ms;
        _set(state: HostedAvatarState.live);
      case NetworkEvent(:final poor, :final rttMs):
        _rttMs = rttMs ?? _rttMs;
        _poorReports = poor ? _poorReports + 1 : 0;
        if (_poorReports > poorReportsAllowed) {
          _fail(FallbackReason.poorNetwork);
        } else {
          _set();
        }
      case MicEvent(:final state):
        _mic = state;
        _set();
      case ErrorEvent(:final code, :final message):
        _lastError = code;
        _fail(switch (code) {
          'permission_denied' => FallbackReason.permissionDenied,
          'webview' || 'sdk_missing' => FallbackReason.webViewFailed,
          'connect_timeout' => FallbackReason.connectTimeout,
          _ => FallbackReason.sessionError,
        });
        if (kDebugMode && message.isNotEmpty) debugPrint('avatar bridge error: $code');
      case EndedEvent(:final reason):
        _fail(reason == 'error' ? FallbackReason.sessionError : FallbackReason.sessionEnded);
    }
  }

  Future<void> _beat(int gen) async {
    final s = _session;
    if (s == null || gen != _generation) return;
    try {
      final used = await api.heartbeat(s.sessionId);
      if (gen != _generation) return;
      _beatFailures = 0;
      if (used != null) {
        _usedSeconds = used;
        _set();
      }
    } on AvatarRefusal catch (r) {
      if (gen == _generation) {
        _lastError = r.code;
        _fail(_reasonFor(r));
      }
    } catch (_) {
      if (gen == _generation && ++_beatFailures > heartbeatFailuresAllowed) _fail(FallbackReason.offline);
    }
  }

  /// The integration point for the stage: speak the coach's reply with the live
  /// face. Returns true when the live face is speaking it; false means the
  /// caller must speak it the usual way (frame avatar + system voice). On an audio
  /// failure the live session is closed (fallback) and false is returned.
  Future<bool> speakReply(String text) async {
    if (!isLive || text.trim().isEmpty) return false;
    final gen = _generation;
    final id = 'r${++_speakSeq}';
    try {
      Uint8List? pending;
      await for (final chunk in audio.synthesize(text, language: language, coachId: coachId)) {
        if (gen != _generation || !isLive) return false;
        if (pending != null) await bridge.send(SpeakCommand.audio(id: id, pcm16: pending, sampleRate: audio.sampleRate));
        pending = chunk;
      }
      if (gen != _generation || !isLive) return false;
      if (pending == null) throw const AvatarAudioUnavailable('empty');
      await bridge.send(SpeakCommand.audio(id: id, pcm16: pending, sampleRate: audio.sampleRate, last: true));
      return true;
    } on AvatarAudioUnavailable {
      if (gen == _generation) await _fail(FallbackReason.audioUnavailable);
      return false;
    }
  }

  /// Debug only: let the vendor speak [text] itself (Anam text-to-speech).
  Future<void> speakVendorText(String text) async {
    if (isLive) await bridge.send(SpeakCommand.text(id: 'v${++_speakSeq}', text: text));
  }

  /// Drops audio the face has not spoken yet (the user started talking or tapped stop).
  Future<void> interrupt() async {
    if (isLive) await bridge.send(const InterruptCommand());
  }

  /// The user collapsed the live video: the session is ended (minutes stop) and the
  /// frame avatar is shown. [start] shows it again.
  Future<void> collapse() => _fail(FallbackReason.collapsed);

  /// The app went to the background: end the live session (no media in the background).
  Future<void> onBackgrounded() async {
    if (showsLiveFace) await _fail(FallbackReason.backgrounded);
  }

  /// Ends the session without a fallback notice (screen closed).
  Future<void> stop() async {
    _generation++;
    await _teardown();
    if (!_disposed) _set(state: HostedAvatarState.idle, activity: AvatarActivity.idle);
  }

  Future<void> _fail(FallbackReason reason) async {
    if (_state == HostedAvatarState.fallback && _fallback == reason) return;
    _generation++;
    await _teardown();
    _set(state: HostedAvatarState.fallback, fallback: reason, activity: AvatarActivity.idle);
  }

  Future<void> _teardown() async {
    _connectTimer?.cancel();
    _beatTimer?.cancel();
    _maxTimer?.cancel();
    _connectTimer = _beatTimer = _maxTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    final s = _session;
    _session = null;
    _beatFailures = 0;
    _poorReports = 0;
    if (s != null) {
      try {
        await bridge.send(const StopCommand());
      } catch (_) {/* the page may already be gone */}
      try {
        final used = await api.end(s.sessionId);
        if (used != null) _usedSeconds = used;
      } catch (_) {/* the Worker settles unreported sessions itself */}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    // Fire and forget: ends the vendor session and the Worker's minute count.
    unawaited(_teardown().then((_) => bridge.dispose()));
    super.dispose();
  }
}
