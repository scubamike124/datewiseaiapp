// Full-app QA sweep (v2), Past conversations: previews and labels are plain
// text (no **markdown**, no OPTIONS line), and deleting a conversation offers
// Undo; the delete button is at least 44x44 on every platform.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/chat_thread.dart';
import 'package:datewise_ai/models/reply_options.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'helpers.dart';

const _reply = '**Ava** here. Try a question about the photo.\n'
    '- Keep it short\n'
    'OPTIONS: Safe | "That trail looks unreal." || Playful | "That view beats my Sunday."';

String _threads() => jsonEncode([
      ChatThread(
        id: 't1',
        title: 'Help with an opener',
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 2),
        messages: [
          ChatMessage(id: 'u', role: MessageRole.user, text: 'Help with an opener', createdAt: DateTime(2026, 11, 1)),
          ChatMessage(id: 'c', role: MessageRole.coach, text: _reply, createdAt: DateTime(2026, 11, 1)),
        ],
      ).toJson(),
    ]);

Future<void> _openHistory(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('chat-menu')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('menu-history')));
  await t.pumpAndSettle();
}

void main() {
  test('plainPreview drops markdown markers and the OPTIONS line', () {
    expect(plainPreview(_reply), 'Ava here. Try a question about the photo. Keep it short');
    expect(plainPreview('# Plan\n> quoted __word__ and `code`'), 'Plan quoted word and code');
    expect(plainPreview('No markdown'), 'No markdown');
  });

  testWidgets('the history preview and its semantics label are plain text', (t) async {
    final handle = t.ensureSemantics();
    await pumpApp(t, prefs: {...onboardedPrefs(), 'dw_threads': _threads()}, tab: AppTab.chat);
    await t.pumpAndSettle();
    await _openHistory(t);
    final preview = find.byKey(const ValueKey('history-preview-t1'));
    expect(t.widget<Text>(preview).data, 'Ava here. Try a question about the photo. Keep it short');
    final tile = find.ancestor(of: preview, matching: find.byType(ListTile));
    final label = t.getSemantics(tile).label;
    expect(label, contains('Ava here.'));
    expect(label, isNot(contains('**')));
    expect(label, isNot(contains('OPTIONS')));
    expect(label, isNot(contains('That trail looks unreal')));
    handle.dispose();
  });

  testWidgets('delete shows Undo; Undo brings the conversation back and reopens it', (t) async {
    final app = await pumpApp(t, prefs: {...onboardedPrefs(), 'dw_threads': _threads()}, tab: AppTab.chat);
    await t.pumpAndSettle();
    await _openHistory(t);
    await t.tap(find.byKey(const ValueKey('history-delete-t1')));
    await t.pumpAndSettle();
    expect(app.state.threads, isEmpty);
    expect(app.storage.loadThreads(), isEmpty, reason: 'deleted from the device at once');
    expect(find.text('Conversation deleted.'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('undo-delete')));
    await t.pumpAndSettle();
    expect(app.state.threads.map((x) => x.id), ['t1']);
    expect(app.state.activeThread?.id, 't1', reason: 'it was the open conversation');
    expect((await StorageService.create()).loadThreads().map((x) => x.id), ['t1'], reason: 'saved again');
    expect(find.text('Help with an opener'), findsWidgets);
  });

  testWidgets('Spanish: "Conversación eliminada." with Deshacer', (t) async {
    final threads = (jsonDecode(_threads()) as List)..first['coachId'] = 'sofia';
    await pumpApp(t, prefs: {...spanishPrefs(), 'dw_threads': jsonEncode(threads)}, tab: AppTab.chat);
    await t.pumpAndSettle();
    await _openHistory(t);
    await t.tap(find.byKey(const ValueKey('history-delete-t1')));
    await t.pumpAndSettle();
    expect(find.text('Conversación eliminada.'), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
  });

  testWidgets('the delete button is at least 44x44, also with desktop/web density', (t) async {
    await pumpApp(t, prefs: {...onboardedPrefs(), 'dw_threads': _threads()}, tab: AppTab.chat);
    await t.pumpAndSettle();
    await _openHistory(t);
    final size = t.getSize(find.byKey(const ValueKey('history-delete-t1')));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}));

  group('Undo after a bulk delete (privacy)', () {
    Future<TestApp> deleteOne(WidgetTester t, {Size size = const Size(390, 844), double scale = 1.0}) async {
      final app = await pumpApp(t, size: size, scale: scale, prefs: {...onboardedPrefs(), 'dw_threads': _threads()}, tab: AppTab.chat);
      await t.pumpAndSettle();
      await _openHistory(t);
      await t.tap(find.byKey(const ValueKey('history-delete-t1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('undo-delete')), findsOneWidget);
      return app;
    }

    Future<void> expectGone(TestApp app) async {
      expect(app.state.threads, isEmpty);
      expect((await StorageService.create()).loadThreads(), isEmpty, reason: 'not written back to the device');
    }

    testWidgets('the "Conversation deleted · Undo" snackbar closes by itself', (t) async {
      await deleteOne(t);
      expect(t.widget<SnackBar>(find.byKey(const ValueKey('conversation-deleted'))).persist, isFalse);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('conversation-deleted')), findsNothing);
    });

    testWidgets('delete, then "Delete all conversations", then Undo: nothing comes back', (t) async {
      final app = await deleteOne(t);
      await app.state.deleteAllConversations();
      await t.pump();
      await t.tap(find.byKey(const ValueKey('undo-delete')));
      await t.pumpAndSettle();
      await expectGone(app);
    });

    testWidgets('delete, then "Delete my data", then Undo: nothing comes back', (t) async {
      final app = await deleteOne(t);
      await app.state.deleteMyData();
      await t.pump();
      // The snackbar may already be gone with the shell; tap it if it is not.
      final undo = find.byKey(const ValueKey('undo-delete'));
      if (undo.evaluate().isNotEmpty) await t.tap(undo, warnIfMissed: false);
      await t.pumpAndSettle();
      await expectGone(app);
    });

    testWidgets('leaving the chat tab closes the Undo snackbar', (t) async {
      await deleteOne(t);
      await t.tap(find.byKey(const ValueKey('tab-you')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('conversation-deleted')), findsNothing);
    });

    testWidgets('on iPhone SE at 2.0 the snackbar floats above the composer', (t) async {
      await deleteOne(t, size: const Size(375, 667), scale: 2.0);
      // The visible bar (the SnackBar widget's own box includes its margin).
      final bar = t.getRect(find
          .descendant(of: find.byKey(const ValueKey('conversation-deleted')), matching: find.byType(Material))
          .first);
      final composer = t.getRect(find.byKey(const ValueKey('composer')));
      expect(bar.bottom, lessThanOrEqualTo(composer.top), reason: 'the composer stays visible and usable');
      expect(t.takeException(), isNull);
    });

    test('AppState: Undo is refused after either bulk delete, allowed otherwise', () async {
      for (final bulk in <String?>[null, 'all', 'mine']) {
        final app = await makeState(prefs: {...onboardedPrefs(), 'dw_threads': _threads()});
        final AppState s = app.state;
        final removed = (await s.deleteThread('t1'))!;
        if (bulk == 'all') await s.deleteAllConversations();
        if (bulk == 'mine') await s.deleteMyData();
        final restored = await s.restoreThread(removed);
        expect(restored, bulk == null, reason: '$bulk');
        expect(s.threads.map((x) => x.id), bulk == null ? ['t1'] : isEmpty, reason: '$bulk');
        expect((await StorageService.create()).loadThreads().map((x) => x.id), bulk == null ? ['t1'] : isEmpty);
        // A second Undo of the same delete does nothing.
        expect(await s.restoreThread(removed), isFalse);
      }
    });
  });
}
