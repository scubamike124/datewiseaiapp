import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lip_sync.dart';
import 'viseme.dart';

/// An event from the native speech-audio path (ios/Runner/AppDelegate.swift).
@immutable
sealed class SpeechAudioEvent {
  const SpeechAudioEvent();

  static SpeechAudioEvent? parse(Object? raw) {
    if (raw is! Map) return null;
    double d(Object? v) => (v as num?)?.toDouble() ?? 0;
    return switch (raw['e']) {
      'start' => SpeechAudioStarted(latency: d(raw['latency'])),
      'levels' => SpeechAudioLevels(d(raw['t0']), d(raw['hop']), [for (final v in (raw['v'] as List? ?? const [])) d(v)]),
      'marker' => SpeechAudioMarker((raw['start'] as num).toInt(), (raw['end'] as num).toInt(), d(raw['t'])),
      'synthesized' => const SpeechAudioSynthesized(),
      'done' => const SpeechAudioDone(),
      'error' => SpeechAudioError('${raw['message']}', started: raw['started'] == true),
      _ => null,
    };
  }
}

/// Playback started: audio time 0 is heard [latency] seconds from now
/// (the output route's latency; larger on Bluetooth headphones).
class SpeechAudioStarted extends SpeechAudioEvent {
  const SpeechAudioStarted({this.latency = 0});
  final double latency;
}

/// Loudness (RMS) of the rendered speech, one value per [hop] seconds from
/// audio time [t0]. Arrives ahead of playback (synthesis is faster).
class SpeechAudioLevels extends SpeechAudioEvent {
  const SpeechAudioLevels(this.t0, this.hop, this.values);
  final double t0;
  final double hop;
  final List<double> values;
}

/// A word starts at audio time [t] (iOS 17 synthesis markers).
class SpeechAudioMarker extends SpeechAudioEvent {
  const SpeechAudioMarker(this.charStart, this.charEnd, this.t);
  final int charStart;
  final int charEnd;
  final double t;
}

/// All of the utterance has been rendered (every level has been sent).
class SpeechAudioSynthesized extends SpeechAudioEvent {
  const SpeechAudioSynthesized();
}

class SpeechAudioDone extends SpeechAudioEvent {
  const SpeechAudioDone();
}

class SpeechAudioError extends SpeechAudioEvent {
  const SpeechAudioError(this.message, {this.started = false});
  final String message;
  final bool started;
}

/// The native speech-audio path: renders the coach's reply with the device's
/// own voice to PCM, plays it, and reports its loudness, so the avatar's jaw
/// follows the real audio. iOS only; replaceable in tests.
abstract class SpeechAudioBackend {
  Stream<SpeechAudioEvent> get events;
  Future<void> speak({required String text, String? voice, required String language, required double rate, required double pitch});
  Future<void> stop();
}

/// The platform-channel implementation.
class ChannelSpeechAudioBackend implements SpeechAudioBackend {
  ChannelSpeechAudioBackend({MethodChannel? method, EventChannel? events})
      : _method = method ?? const MethodChannel('datewise/speech_audio'),
        _eventChannel = events ?? const EventChannel('datewise/speech_audio/events');

  final MethodChannel _method;
  final EventChannel _eventChannel;
  Stream<SpeechAudioEvent>? _events;

  @override
  Stream<SpeechAudioEvent> get events => _events ??= _eventChannel
      .receiveBroadcastStream()
      .map(SpeechAudioEvent.parse)
      .where((e) => e != null)
      .cast<SpeechAudioEvent>()
      .asBroadcastStream();

  @override
  Future<void> speak({required String text, String? voice, required String language, required double rate, required double pitch}) =>
      _method.invokeMethod<void>('speak', {'text': text, 'voice': voice, 'language': language, 'rate': rate, 'pitch': pitch});

  @override
  Future<void> stop() => _method.invokeMethod<void>('stop');
}

/// Loudness and timing of the utterance being played: the jaw opening, and
/// the mapping from audio time to the viseme plan.
///
/// Mapping, best first:
///  1. word markers (iOS 17): piecewise linear between word starts;
///  2. otherwise dynamic time warping between the loudness of the audio and
///     the plan's own activity (speech vs. pauses, and its syllable
///     envelope), at 20 ms steps. Synthesis runs ahead of playback, so the
///     loudness of most of the reply is known early; the warp is recomputed
///     as more arrives (open end).
class AudioAlignment {
  AudioAlignment(this.timeline) : _planFeat = _planFeatures(timeline);

  final VisemeTimeline timeline;
  final List<double> _levels = [];
  double _hop = 0.01;
  double _peak = 0;
  final Map<int, double> _markers = {}; // word index -> audio time
  final List<double> _planFeat;
  List<double> _map = const []; // plan time for each audio step
  int _mappedSteps = 0;
  bool _complete = false;

  /// DTW step, seconds.
  static const double step = 0.02;

  /// Level below this fraction of the utterance's peak counts as silence.
  static const double silenceRatio = 0.12;

  /// Plan activity per [step]: 0 in pauses, 0.5..1 in words (syllable bumps).
  static List<double> _planFeatures(VisemeTimeline tl) {
    final n = (tl.duration / step).ceil() + 1;
    final out = List<double>.filled(n, 0);
    var w = 0;
    for (var i = 0; i < n; i++) {
      final t = i * step;
      while (w < tl.words.length && tl.words[w].end < t) {
        w++;
      }
      final inWord = w < tl.words.length && tl.words[w].start <= t && t <= tl.words[w].end;
      out[i] = inWord ? 0.7 + 0.3 * tl.jawAt(t).clamp(0.0, 1.0) : 0;
    }
    return out;
  }

  bool get hasLevels => _levels.isNotEmpty;

  /// Appends loudness values starting at audio time [t0].
  void addLevels(double t0, double hop, List<double> values) {
    _hop = hop;
    final startIndex = (t0 / hop).round();
    while (_levels.length < startIndex) {
      _levels.add(0);
    }
    for (final v in values) {
      _peak = math.max(_peak, v);
      _levels.add(v);
    }
    // Re-warp at the start, then only every [rewarpEvery] of new audio
    // (and once more on [complete]): the warp runs on the UI isolate.
    final steps = (_levels.length * _hop / step).floor();
    if (_mappedSteps == 0 || (steps - _mappedSteps) * step >= rewarpEvery) _warp(steps);
  }

  /// All levels have arrived: warp once more with both ends fixed (the
  /// whole audio maps onto the whole plan).
  void complete() {
    _complete = true;
    _warp((_levels.length * _hop / step).floor());
  }

  /// Audio activity per [step], comparable to the plan's.
  List<double> _audioFeatures(int steps) {
    final out = List<double>.filled(steps, 0);
    final per = math.max(1, (step / _hop).round());
    for (var i = 0; i < steps; i++) {
      var m = 0.0;
      for (var k = i * per; k < math.min(_levels.length, (i + 1) * per); k++) {
        m = math.max(m, _levels[k]);
      }
      final l = _peak > 0 ? m / _peak : 0.0;
      out[i] = l > silenceRatio ? 0.7 + 0.3 * math.min(1.0, l / 0.8) : 0;
    }
    return out;
  }

  /// Largest DTW matrix (cells); longer replies are warped at a coarser
  /// step (about 3 MB at most).
  static const int maxCells = 250000;

  /// New audio (seconds) that triggers a fresh warp while synthesis runs.
  static const double rewarpEvery = 1.0;

  void _warp(int steps) {
    if (steps <= 0 || _planFeat.isEmpty) return;
    final fullA = _audioFeatures(steps);
    // Coarser steps for long replies, so memory and time stay bounded.
    final k = math.max(1, math.sqrt(fullA.length * _planFeat.length / maxCells).ceil());
    List<double> down(List<double> x) => [for (var i = 0; i < x.length; i += k) x[i]];
    final a = down(fullA), p = down(_planFeat);
    final n = a.length, m = p.length;
    const big = 1e18;
    const pen = 0.15; // cost of a non-diagonal step (prefer an even pace)
    // Rows = audio, cols = plan; flat arrays.
    final d = Float64List(n * m)..fillRange(0, n * m, big);
    final back = Uint8List(n * m);
    d[0] = (a[0] - p[0]).abs();
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < m; j++) {
        if (i == 0 && j == 0) continue;
        var best = big;
        var from = 0;
        if (i > 0 && j > 0 && d[(i - 1) * m + j - 1] < best) {
          best = d[(i - 1) * m + j - 1];
          from = 0;
        }
        if (i > 0 && d[(i - 1) * m + j] + pen < best) {
          best = d[(i - 1) * m + j] + pen;
          from = 1;
        }
        if (j > 0 && d[i * m + j - 1] + pen < best) {
          best = d[i * m + j - 1] + pen;
          from = 2;
        }
        d[i * m + j] = best + (a[i] - p[j]).abs();
        back[i * m + j] = from;
      }
    }
    // Both ends fixed once all the audio is known; before that the plan may
    // not be reached yet (open end, normalized by path length, since the
    // cumulative cost alone would always prefer ending early).
    var jEnd = _complete ? m - 1 : 0;
    if (!_complete) {
      for (var j = 1; j < m; j++) {
        if (d[(n - 1) * m + j] / (n + j) < d[(n - 1) * m + jEnd] / (n + jEnd)) jEnd = j;
      }
    }
    final coarse = List<double>.filled(n, 0);
    var i = n - 1, j = jEnd;
    while (i >= 0 && j >= 0) {
      coarse[i] = math.max(coarse[i], j * step * k);
      if (i == 0 && j == 0) break;
      switch (back[i * m + j]) {
        case 0:
          i--;
          j--;
        case 1:
          i--;
        default:
          j--;
      }
    }
    // Back to [step] resolution.
    _map = [
      for (var x = 0; x < fullA.length; x++)
        () {
          final c = x / k, c0 = c.floor().clamp(0, n - 1), c1 = (c0 + 1).clamp(0, n - 1);
          final f = c - c0;
          return coarse[c0] * (1 - f) + coarse[c1] * f;
        }(),
    ];
    _mappedSteps = steps;
    _closures = null;
  }

  List<(double, double)>? _closures;

  /// How far a planned lip closure may move to meet a clear dip in the
  /// loudness. Kept small: in the offline evaluation a wider search (120 ms)
  /// moved closures away from the real M/B/P more often than onto them.
  static const double closureSearch = 0.06;

  /// Lips-closed windows (audio seconds): every planned M/B/P closure at
  /// the audio time the current mapping gives it, moved onto a clear dip in
  /// the loudness within ±[closureSearch] when there is one (closed lips
  /// silence the voice; an "m" is voiced, so it often has no dip and stays
  /// where the plan puts it). Empty until a mapping exists.
  List<(double, double)> closures() {
    final cached = _closures;
    if (cached != null) return cached;
    final out = <(double, double)>[];
    final len = _levels.length * _hop;
    if (len <= 0) return out;
    // Plan time at every audio step, through markers or the warp.
    final steps = (len / step).ceil();
    final dense = [for (var i = 0; i < steps; i++) planTime(i * step) ?? -1.0];
    if (dense.every((p) => p < 0)) return out;
    double audioAt(double plan) {
      for (var i = 0; i < dense.length; i++) {
        if (dense[i] >= plan) return i * step;
      }
      return len;
    }

    double smooth(int i) {
      var sum = 0.0, n = 0;
      for (var k = i - 1; k <= i + 1; k++) {
        if (k >= 0 && k < _levels.length) {
          sum += _levels[k];
          n++;
        }
      }
      return n == 0 ? 1e9 : sum / n;
    }

    for (final c in timeline.cues) {
      if (c.viseme != Viseme.mbp) continue;
      final a0 = audioAt(c.start), a1 = audioAt(c.end);
      final d = math.max(0.05, a1 - a0);
      final mid = (a0 + a1) / 2;
      var best = mid, bestLevel = double.infinity;
      final around = <double>[];
      for (var t = mid - closureSearch; t <= mid + closureSearch; t += _hop) {
        final l = smooth((t / _hop).round());
        around.add(l);
        if (l < bestLevel) {
          bestLevel = l;
          best = t;
        }
      }
      around.sort();
      final median = around.isEmpty ? 0.0 : around[around.length ~/ 2];
      final clearDip = bestLevel < 0.3 * median;
      final center = clearDip ? best : mid;
      out.add((center - d / 2, center + d / 2));
    }
    return _closures = out;
  }

  /// Whether audio time [t] falls in a (snapped) lip closure.
  bool inClosure(double t) {
    for (final (a, b) in closures()) {
      if (t >= a && t < b) return true;
    }
    return false;
  }

  void addMarker(int charStart, double t) {
    final k = timeline.wordAtChar(charStart);
    if (k >= 0 && t >= 0) {
      _markers[k] = t;
      _closures = null;
    }
  }

  /// Markers that make sense: in word order, and not past the audio
  /// (a unit mistake would put them there); otherwise none are used.
  Map<int, double> _validMarkers() {
    if (_markers.isEmpty) return const {};
    final ks = _markers.keys.toList()..sort();
    final audioLen = _levels.length * _hop;
    for (var i = 0; i < ks.length; i++) {
      final t = _markers[ks[i]]!;
      if (i > 0 && t < _markers[ks[i - 1]]!) return const {};
      if (_complete && t > audioLen + 0.1) return const {};
    }
    return _markers;
  }

  /// Loudness at audio time [t], 0..1 relative to the utterance's peak.
  double level(double t) {
    if (_levels.isEmpty || _peak <= 0) return 0;
    final x = t / _hop;
    final i = x.floor();
    if (i < 0 || i + 1 >= _levels.length) return i == _levels.length - 1 && i >= 0 ? _levels[i] / _peak : 0;
    final f = x - i;
    return ((_levels[i] * (1 - f) + _levels[i + 1] * f) / _peak).clamp(0.0, 1.0);
  }

  /// Plan time for audio time [t], or null when nothing maps yet.
  double? planTime(double t) {
    final markers = _validMarkers();
    if (markers.length >= 2 || (markers.isNotEmpty && _map.isEmpty)) {
      final ks = markers.keys.toList()..sort();
      int? prev;
      for (final k in ks) {
        if (markers[k]! <= t) prev = k;
      }
      if (prev != null) {
        final i = ks.indexOf(prev);
        final w = timeline.words[prev];
        if (i + 1 < ks.length) {
          final next = ks[i + 1];
          final t0 = markers[prev]!, t1 = markers[next]!;
          final p1 = timeline.words[next].start;
          if (t1 > t0) return w.start + (t - t0) / (t1 - t0) * (p1 - w.start);
        }
        return w.start + (t - markers[prev]!);
      }
    }
    if (_map.isEmpty || t < 0) return null;
    final x = t / step;
    final i = x.floor();
    if (i + 1 < _map.length) {
      final f = x - i;
      return _map[i] * (1 - f) + _map[i + 1] * f;
    }
    // Beyond the audio received so far: continue at the planned speed.
    return _map.last + (t - (_map.length - 1) * step);
  }
}
