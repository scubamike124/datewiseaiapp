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
  const AvatarManifest({
    required this.coachId,
    required this.width,
    required this.height,
    required this.patches,
    this.mouth,
    this.mouthWidth,
    this.sourceWidth,
    this.sourceHeight,
  });

  final String coachId;

  /// Pixel size of the portrait the patches were generated from.
  final int width;
  final int height;
  final Map<String, AvatarPatch> patches;

  /// Pixel size of the portrait file itself, when the generator scaled it
  /// down to [width] x [height] first (null: the same as [width]/[height]).
  final int? sourceWidth;
  final int? sourceHeight;

  /// Center of the lips and their width in the portrait (pixels), for the
  /// jaw drop; null in manifests from older generator versions.
  final ui.Offset? mouth;
  final double? mouthWidth;

  static String dir(String coachId) => 'assets/avatar/$coachId';
  String assetFor(String patch) => '${dir(coachId)}/$patch.jpg';

  static final Map<String, Future<AvatarManifest?>> _manifests = {};

  /// Just the manifest (small JSON, cached): enough to place the still
  /// portrait like the animated one, without decoding any frame.
  static Future<AvatarManifest?> load(Coach coach, {AssetBundle? bundle}) => _manifests.putIfAbsent(
      coach.id,
      () => (bundle ?? rootBundle)
          .loadString('${dir(coach.id)}/manifest.json')
          .then<AvatarManifest?>((j) => parse(coach.id, j))
          .catchError((Object _) => null));

  static AvatarManifest parse(String coachId, String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final frames = (m['frames'] as Map<String, dynamic>? ?? const {});
    final mouth = m['mouth'] as List?;
    return AvatarManifest(
      coachId: coachId,
      width: (m['width'] as num).toInt(),
      height: (m['height'] as num).toInt(),
      mouth: mouth == null ? null : ui.Offset((mouth[0] as num).toDouble(), (mouth[1] as num).toDouble()),
      mouthWidth: (m['mouth_width'] as num?)?.toDouble(),
      sourceWidth: (m['source_width'] as num?)?.toInt(),
      sourceHeight: (m['source_height'] as num?)?.toInt(),
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

  final Map<ui.Image, ui.ImageShader> _shaders = {};
  static final _identity = Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  /// A texture shader for [image] (cached), for the jaw-drop mesh.
  ui.ImageShader shaderFor(ui.Image image) => _shaders.putIfAbsent(
      image, () => ui.ImageShader(image, ui.TileMode.clamp, ui.TileMode.clamp, _identity, filterQuality: ui.FilterQuality.medium));

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final sh in _shaders.values) {
      sh.dispose();
    }
    _shaders.clear();
    base.dispose();
    for (final i in images.values) {
      i.dispose();
    }
  }

  static Future<AvatarFrames?> _load(Coach coach, AssetBundle bundle) async {
    final decoded = <ui.Image>[];
    try {
      final manifest = AvatarManifest.parse(coach.id, await bundle.loadString('${AvatarManifest.dir(coach.id)}/manifest.json'));
      // The portrait file must be the one the frames were made from (same
      // pixel size). It is decoded at the size the frames were made for
      // (tool/avatar/gen_frames.py --max-width), which can be smaller than
      // the file, so a large final portrait costs no extra memory here.
      final data = await bundle.load(coach.heroAsset);
      final buffer = await ui.ImmutableBuffer.fromUint8List(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final ui.Image base;
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final fileSize = (descriptor.width, descriptor.height);
        if (fileSize != (manifest.sourceWidth ?? manifest.width, manifest.sourceHeight ?? manifest.height)) {
          return null;
        }
        final codec = await descriptor.instantiateCodec(targetWidth: manifest.width, targetHeight: manifest.height);
        try {
          base = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor?.dispose();
        buffer.dispose();
      }
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
