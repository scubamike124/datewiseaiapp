// Full-app QA sweep (v2), accessibility: a failed or stopped reply with one
// action announces the notice and the button separately (the notice used to
// be merged into the button's label), and the plan status color's contrast.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/chat_thread.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/theme/app_theme.dart';

import 'a11y_test.dart' show contrast;
import 'helpers.dart';

String _threadWith(ChatMessage last) => jsonEncode([
      ChatThread(
        id: 't1',
        title: 'Opener',
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
        messages: [
          ChatMessage(id: 'u', role: MessageRole.user, text: 'Give me a strong opener', createdAt: DateTime(2026, 11, 1)),
          last,
        ],
      ).toJson(),
    ]);

void main() {
  for (final (name, status, notice) in [
    ('stopped', MessageStatus.stopped, 'The reply was stopped. Your message is saved.'),
    ('failed', MessageStatus.failed, "Couldn't reach your coach. Your message is saved. Try again in a moment."),
  ]) {
    testWidgets('$name reply: the notice and "Try again" are separate semantics nodes', (t) async {
      final handle = t.ensureSemantics();
      await pumpApp(t,
          prefs: {
            ...onboardedPrefs(),
            'dw_threads': _threadWith(
                ChatMessage(id: 'c', role: MessageRole.coach, text: '', createdAt: DateTime(2026, 11, 1), status: status)),
          },
          tab: AppTab.chat);
      await t.pumpAndSettle();
      final retry = find.byKey(const ValueKey('retry'));
      expect(retry, findsOneWidget);
      final button = t.getSemantics(retry);
      expect(button.label, 'Try again');
      expect(button.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(button.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      final noticeText = t.widget<Text>(find.byKey(const ValueKey('reply-failed-notice'))).data!;
      if (status == MessageStatus.stopped) expect(noticeText, notice);
      final noticeNode = t.getSemantics(find.byKey(const ValueKey('reply-failed-notice')));
      expect(noticeNode.id, isNot(button.id));
      expect(noticeNode.label, contains(noticeText));
      expect(noticeNode.getSemanticsData().flagsCollection.isButton, isFalse, reason: 'the notice is not part of the button');
      handle.dispose();
    });
  }

  // QA measured ES "Pendiente" at 2.87:1 on iPhone SE. That row sat under the
  // translucent tab bar (content scrolls behind it), which dims it; scrolled
  // into view, the token is #9C8B82 on the card's #1E1518, 5.47:1.
  testWidgets('Progress plan status ("Pendiente") uses faint on the card surface, above 4.5:1', (t) async {
    await pumpApp(t, size: const Size(375, 667), prefs: spanishPrefs(), tab: AppTab.progress);
    await t.pumpAndSettle();
    final status = find.byKey(const ValueKey('progress-plan-status-1'));
    await t.ensureVisible(status);
    await t.pumpAndSettle();
    final text = t.widget<Text>(status);
    expect(text.data, 'Pendiente');
    expect(text.style!.color, AppColors.faint);
    expect(contrast(AppColors.faint, AppColors.surface), greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.faint, AppColors.surface), closeTo(5.47, 0.02));
    // Fully above the tab bar once scrolled into view.
    final bar = t.getRect(find.byKey(const ValueKey('tab-progress')).first);
    expect(t.getRect(status).bottom, lessThan(bar.top));
  });
}
