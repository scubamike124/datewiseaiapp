import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:datewise_ai/avatar/coach_clips.dart';
import 'package:datewise_ai/l10n/app_localizations.dart';
import 'package:datewise_ai/widgets/coach_clip_player.dart';

/// A fake video platform that records every call, so the tests can check audio order without a device.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  final List<String> log = [];
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = ++_next;
    log.add('create:$id');
    return id;
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => create(options.dataSource);

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
        VideoEvent(eventType: VideoEventType.initialized, duration: const Duration(seconds: 2), size: const Size(480, 600)),
      );

  @override
  Future<void> dispose(int playerId) async => log.add('dispose:$playerId');

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => log.add('play:$playerId');

  @override
  Future<void> pause(int playerId) async => log.add('pause:$playerId');

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async => log.add('speed:$playerId:$speed');

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Color(0xFF000000));
}

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  late _FakeVideoPlatform fake;

  setUp(() {
    fake = _FakeVideoPlatform();
    VideoPlayerPlatform.instance = fake;
  });

  testWidgets('switching coaches pauses and releases the previous clip before the next one is created', (tester) async {
    await tester.pumpWidget(_host(CoachClipPlayer(clip: CoachClips.ethan)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach-clip-toggle')));
    await tester.pump();
    expect(fake.log, contains('play:1'));

    await tester.pumpWidget(_host(CoachClipPlayer(clip: CoachClips.diego)));
    // Let the release and the new load complete: real async steps, pumped in small slices.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 10));
    }

    final pauseAt = fake.log.indexOf('pause:1');
    final disposeAt = fake.log.indexOf('dispose:1');
    final createAt = fake.log.indexOf('create:2');
    expect(pauseAt, isNonNegative, reason: 'the previous clip must be paused');
    expect(disposeAt, greaterThan(pauseAt), reason: 'it is released only after it is paused');
    expect(createAt, greaterThan(disposeAt), reason: 'the new clip loads only after the old one is released');
    expect(fake.log.where((e) => e == 'play:2'), isEmpty, reason: 'the new clip must not start by itself');
  });

  testWidgets('leaving the coaches tab pauses playback and reports it to the screen', (tester) async {
    final reports = <bool>[];
    Widget player(bool paused) => _host(CoachClipPlayer(
          clip: CoachClips.ethan,
          paused: paused,
          onPlaybackChanged: reports.add,
        ));

    await tester.pumpWidget(player(false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach-clip-toggle')));
    await tester.pumpAndSettle();
    expect(reports.last, isTrue);

    await tester.pumpWidget(player(true));
    await tester.pumpAndSettle();
    expect(fake.log, contains('pause:1'));
    expect(reports.last, isFalse);
  });

  testWidgets('controls stay visible, follow the real state, and use localized labels', (tester) async {
    await tester.pumpWidget(_host(CoachClipPlayer(clip: CoachClips.ethan)));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('coach-clip-toggle'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<IconButton>(toggle).tooltip, 'Play clip');

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(toggle).tooltip, 'Pause clip');
    expect(find.bySemanticsLabel('Reference'), findsOneWidget);
  });

  testWidgets('no clip starts on its own, and the Spanish clips are never sped up', (tester) async {
    await tester.pumpWidget(_host(CoachClipPlayer(clip: CoachClips.sofia)));
    await tester.pumpAndSettle();
    expect(fake.log.where((e) => e.startsWith('play:')), isEmpty);
    expect(fake.log.where((e) => e.startsWith('speed:')), isEmpty);
  });
}
