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
///
/// Only one coach's frames are kept: acquiring another coach disposes the
/// previous coach's images once nobody holds them, and the last [release]
/// (the voice stage closing) disposes them too.
class AvatarFrames {
  AvatarFrames._(this.manifest, this.base, this.images);

  final AvatarManifest manifest;
  final ui.Image base;
  final Map<String, ui.Image> images;
  bool _disposed = false;

  static String? _id;
  static Future<AvatarFrames?>? _future;
  static int _holders = 0;

  /// Loads (or reuses) a coach's portrait and patches and counts the caller
  /// as a holder; pair with [release]. Null when the coach has no generated
  /// frames, or the portrait was replaced without regenerating them (its size
  /// no longer matches): the caller then shows the still portrait.
  static Future<AvatarFrames?> acquire(Coach coach, {AssetBundle? bundle}) {
    if (_id != coach.id) {
      _disposeCurrent();
      _id = coach.id;
      _future = _load(coach, bundle ?? rootBundle);
      _holders = 0;
    }
    _holders++;
    return _future!;
  }

  /// One holder of [coachId]'s frames is done; the last one frees them.
  static void release(String coachId) {
    if (coachId != _id) return;
    _holders--;
    if (_holders <= 0) _disposeCurrent();
  }

  static void _disposeCurrent() {
    final f = _future;
    _id = null;
    _future = null;
    _holders = 0;
    f?.then((frames) => frames?._dispose());
  }

  /// Loads without holding (tests and the offline demo renderer).
  @visibleForTesting
  static Future<AvatarFrames?> load(Coach coach, {AssetBundle? bundle}) => _load(coach, bundle ?? rootBundle);

  @visibleForTesting
  static void clearCache() => _disposeCurrent();

  @visibleForTesting
  static String? get heldCoach => _id;

  bool get isDisposed => _disposed;

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    base.dispose();
    for (final i in images.values) {
      i.dispose();
    }
  }

  static Future<AvatarFrames?> _load(Coach coach, AssetBundle bundle) async {
    final decoded = <ui.Image>[];
    try {
      final manifest = AvatarManifest.parse(coach.id, await bundle.loadString('${AvatarManifest.dir(coach.id)}/manifest.json'));
      final base = await _decode(bundle, coach.heroAsset);
      decoded.add(base);
      if (base.width != manifest.width || base.height != manifest.height) {
        base.dispose();
        return null;
      }
      final images = <String, ui.Image>{};
      for (final n in manifest.patches.keys) {
        final img = await _decode(bundle, manifest.assetFor(n));
        decoded.add(img);
        images[n] = img;
      }
      return AvatarFrames._(manifest, base, images);
    } catch (_) {
      // Free whatever was decoded before the failure.
      for (final i in decoded) {
        i.dispose();
      }
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
    if (name == null || _disposed) return null;
    final img = images[name];
    final p = manifest.patches[name];
    return img == null || p == null ? null : (img, p);
  }
}
