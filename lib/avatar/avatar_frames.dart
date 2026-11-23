import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/coach.dart';

/// Which part of the face a patch replaces.
enum AvatarRegion { mouth, eyes, head }

/// One generated patch: a small photo of part of the portrait, and where it
/// goes (pixel rectangle in the portrait).
@immutable
class AvatarPatch {
  const AvatarPatch(this.name, this.region, this.rect);
  final String name;
  final AvatarRegion region;
  final ui.Rect rect;
}

/// `assets/avatar/<coach>/manifest.json`, written by tool/avatar/gen_frames.py.
@immutable
class AvatarManifest {
  const AvatarManifest({required this.coachId, required this.width, required this.height, required this.patches});

  final String coachId;

  /// Pixel size of the portrait the patches were generated from.
  final int width;
  final int height;
  final Map<String, AvatarPatch> patches;

  static String dir(String coachId) => 'assets/avatar/$coachId';
  String assetFor(String patch) => '${dir(coachId)}/$patch.jpg';

  static AvatarManifest parse(String coachId, String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final frames = (m['frames'] as Map<String, dynamic>? ?? const {});
    return AvatarManifest(
      coachId: coachId,
      width: (m['width'] as num).toInt(),
      height: (m['height'] as num).toInt(),
      patches: {
        for (final e in frames.entries)
          e.key: AvatarPatch(
            e.key,
            AvatarRegion.values.byName((e.value as Map<String, dynamic>)['region'] as String),
            () {
              final r = ((e.value as Map<String, dynamic>)['rect'] as List).map((v) => (v as num).toDouble()).toList();
              return ui.Rect.fromLTWH(r[0], r[1], r[2], r[3]);
            }(),
          ),
      },
    );
  }
}

/// The decoded portrait and every patch of one coach, ready to paint.
class AvatarFrames {
  AvatarFrames._(this.manifest, this.base, this.images);

  final AvatarManifest manifest;
  final ui.Image base;
  final Map<String, ui.Image> images;

  static final Map<String, Future<AvatarFrames?>> _cache = {};

  /// Loads (once per coach, then cached) the portrait and its patches.
  /// Null when the coach has no generated frames, or when the portrait was
  /// replaced without regenerating them (its size no longer matches): the
  /// caller then shows the still portrait.
  static Future<AvatarFrames?> load(Coach coach, {AssetBundle? bundle}) =>
      _cache.putIfAbsent(coach.id, () => _load(coach, bundle ?? rootBundle));

  /// Starts decoding a coach's frames early (e.g. when voice mode opens).
  static void preload(Coach coach, {AssetBundle? bundle}) => unawaited(load(coach, bundle: bundle));

  @visibleForTesting
  static void clearCache() => _cache.clear();

  static Future<AvatarFrames?> _load(Coach coach, AssetBundle bundle) async {
    try {
      final manifest = AvatarManifest.parse(coach.id, await bundle.loadString('${AvatarManifest.dir(coach.id)}/manifest.json'));
      final base = await _decode(bundle, coach.heroAsset);
      if (base.width != manifest.width || base.height != manifest.height) {
        base.dispose();
        return null;
      }
      final entries = await Future.wait(manifest.patches.keys.map((n) async => MapEntry(n, await _decode(bundle, manifest.assetFor(n)))));
      return AvatarFrames._(manifest, base, Map.fromEntries(entries));
    } catch (_) {
      _cache.remove(coach.id);
      return null;
    }
  }

  static Future<ui.Image> _decode(AssetBundle bundle, String asset) async {
    final data = await bundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// The patch image and placement for [name], or null if not generated.
  (ui.Image, AvatarPatch)? patch(String? name) {
    if (name == null) return null;
    final img = images[name];
    final p = manifest.patches[name];
    return img == null || p == null ? null : (img, p);
  }
}
