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
}
