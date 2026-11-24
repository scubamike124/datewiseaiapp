// The iOS launch screen is branded, not Flutter's placeholder (the build
// warned "Launch image is set to the default placeholder icon").

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/theme/app_theme.dart';

const _dir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

/// Width and height from a PNG's IHDR chunk.
(int, int) _pngSize(File f) {
  final b = ByteData.sublistView(f.readAsBytesSync());
  expect(b.getUint32(0), 0x89504E47, reason: '${f.path} is a PNG');
  return (b.getUint32(16), b.getUint32(20));
}

void main() {
  test('launch images are the 120 pt brand mark at 1x/2x/3x, not the 1x1 placeholder', () {
    for (final (name, px) in [('LaunchImage.png', 120), ('LaunchImage@2x.png', 240), ('LaunchImage@3x.png', 360)]) {
      final f = File('$_dir/$name');
      expect(_pngSize(f), (px, px), reason: name);
      // Lightweight: well under 200 KB each.
      expect(f.lengthSync(), lessThan(200 * 1024), reason: name);
    }
  });

  test('the launch storyboard uses the app background color and the 120 pt image', () {
    final sb = File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
    final m = RegExp(r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" blue="([\d.]+)" alpha="1"').firstMatch(sb)!;
    final bg = AppColors.background;
    int c(String v) => (double.parse(v) * 255).round();
    expect([c(m[1]!), c(m[2]!), c(m[3]!)], [(bg.r * 255).round(), (bg.g * 255).round(), (bg.b * 255).round()]);
    expect(sb, contains('image="LaunchImage"'));
    expect(sb, contains('<image name="LaunchImage" width="120" height="120"/>'));
    expect(File('ios/Runner/Info.plist').readAsStringSync(), contains('<string>LaunchScreen</string>'));
  });
}
