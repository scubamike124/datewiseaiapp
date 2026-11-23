// Final design review (v2) fixes: the snackbar action is readable (gold on
// the dark surface), the Home greeting keeps whole words at 2.0 in every
// variant, the voice-quality row sits in Coaching, the ES under-18 dialog
// centers its labels and stacks with the action first, the ES "deleted"
// snackbar keeps whole words, "con IA" never orphans "IA", and the
// `screen=chat-limit` review mode shows a limit notice with the paywall.
//
// The real Inter and Newsreader fonts are loaded, so line breaks match the
// app.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/dev/review_mode.dart';
import 'package:datewise_ai/l10n/app_localizations_en.dart';
import 'package:datewise_ai/l10n/app_localizations_es.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/chat_thread.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/theme/app_theme.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'a11y_test.dart' show contrast;
import 'helpers.dart';
import 'ipad_and_large_text_test.dart' show lineCount;
import 'qa_sweep_word_break_test.dart' show wordProblems;

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await loader.load();
}

const _se = Size(375, 667);

void main() {
  setUpAll(() async {
    await _loadFont('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']);
    await _loadFont('Newsreader', ['Newsreader-Regular.ttf', 'Newsreader-Medium.ttf', 'Newsreader-Italic.ttf']);
  });

  group('snackbar action contrast', () {
    test('the theme colors actions gold, at least 4.5:1 on the snackbar', () {
      final theme = AppTheme.dark.snackBarTheme;
      expect(theme.actionTextColor, AppColors.gold);
      expect(contrast(theme.actionTextColor!, theme.backgroundColor!), greaterThanOrEqualTo(4.5));
    });

    testWidgets('a SnackBarAction renders in gold', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => ScaffoldMessenger.of(c).showSnackBar(
                  SnackBar(content: const Text('Deleted'), action: SnackBarAction(label: 'Undo', onPressed: () {}))),
              child: const Text('show'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('show'));
      await t.pumpAndSettle();
      final undo = t.widget<RichText>(find.descendant(of: find.byType(SnackBarAction), matching: find.byType(RichText)));
      final color = undo.text.style?.color ?? (undo.text as TextSpan).children?.first.style?.color;
      expect(color, AppColors.gold);
    });
  });

  group('Home greeting at 2.0', () {
    for (final (lang, l) in [('en', AppLocalizationsEn()), ('es', AppLocalizationsEs())]) {
      for (final tablet in [false, true]) {
        for (final g in [l.greetingMorning, l.greetingAfternoon, l.greetingEvening]) {
          testWidgets('[$lang ${tablet ? 'iPad' : 'iPhone'}] "$g" keeps whole words', (t) async {
            final width = tablet ? 340.0 : 240.0;
            await t.pumpWidget(MaterialApp(
              theme: AppTheme.dark,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: WholeWordsText(g,
                        key: const ValueKey('g'),
                        maxWidth: width,
                        style: AppText.display.copyWith(fontSize: tablet ? 42 : 34, height: 1.05)),
                  ),
                ),
              ),
            ));
            expect(wordProblems(t, find.byKey(const ValueKey('g'))), isEmpty);
          });
        }
      }
    }

    for (final (lang, prefs) in [('en', onboardedPrefs()), ('es', spanishPrefs())]) {
      for (final (name, size, maxWidth) in [('iPhone', const Size(390, 844), 240.0), ('iPad', const Size(1032, 1376), 340.0)]) {
        testWidgets('[$lang $name] Home uses whole words for the greeting', (t) async {
          await pumpApp(t, size: size, scale: 2.0, prefs: prefs);
          await t.pumpAndSettle();
          final greeting = find.byKey(const ValueKey('home-greeting'));
          expect(t.widget<WholeWordsText>(greeting).maxWidth, maxWidth);
          expect(wordProblems(t, greeting), isEmpty);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('More natural coach voices sits in the Coaching group', (t) async {
    await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.you);
    await t.pumpAndSettle();
    final voice = find.byKey(const ValueKey('row-voice-quality'));
    await t.ensureVisible(voice);
    await t.pumpAndSettle();
    final coach = t.getRect(find.byKey(const ValueKey('row-coach')));
    final row = t.getRect(voice);
    final memory = t.getRect(find.text(AppLocalizationsEn().sectionMemory));
    expect(row.top, greaterThan(coach.top));
    expect(row.bottom, lessThan(memory.top), reason: 'above the Memory group');
  });

  group('ES under-18 dialog on iPhone SE', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('at $scale: action first, centered, one line', (t) async {
        await pumpScreen(t, const OnboardingScreen(initialStep: 2),
            size: _se, scale: scale, prefs: spanishPrefs(), locale: const Locale('es'));
        await t.pumpAndSettle();
        final under = find.byKey(const ValueKey('age-under'));
        await t.ensureVisible(under);
        await t.pumpAndSettle();
        await t.tap(under);
        await t.pumpAndSettle();
        final action = find.byKey(const ValueKey('confirm-action'));
        final cancel = find.byKey(const ValueKey('confirm-cancel'));
        expect(find.descendant(of: action, matching: find.text('Sí, tengo menos de 18')), findsOneWidget);
        for (final b in [action, cancel]) {
          final text = t.widget<Text>(find.descendant(of: b, matching: find.byType(Text)));
          expect(text.textAlign, TextAlign.center);
          // One line at 1.0; at 2.0 a long label may wrap, between words,
          // each line centered under the other.
          expect(lineCount(t, b), scale == 1.0 ? 1 : lessThanOrEqualTo(2), reason: '${text.data}');
        }
        final a = t.getRect(action);
        final c = t.getRect(cancel);
        if (a.top != c.top) {
          // Stacked: the action above Cancel, both centered in the dialog.
          expect(a.bottom, lessThanOrEqualTo(c.top + 0.5));
          expect(a.center.dx, closeTo(c.center.dx, 0.5));
        } else {
          expect(a.left, greaterThan(c.left));
        }
        expect(wordProblems(t, find.byType(AlertDialog)), isEmpty);
        expect(t.takeException(), isNull);
      });
    }

    test('the dialog stacks with the action on top when the row overflows', () {
      // Read from the source: the AlertDialog's overflow settings.
      final src = File('lib/widgets/dw.dart').readAsStringSync();
      expect(src, contains('actionsOverflowDirection: VerticalDirection.up'));
      expect(src, contains('actionsOverflowAlignment: OverflowBarAlignment.center'));
    });
  });

  testWidgets('ES "Conversación eliminada." at 2.0 keeps whole words', (t) async {
    final threads = jsonEncode([
      ChatThread(
        id: 't1',
        title: 'Un saludo',
        coachId: 'sofia',
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 2),
        messages: [
          ChatMessage(id: 'u', role: MessageRole.user, text: 'Hola', createdAt: DateTime(2026, 11, 1)),
          ChatMessage(id: 'c', role: MessageRole.coach, text: 'Hola, soy Sofía.', createdAt: DateTime(2026, 11, 1)),
        ],
      ).toJson(),
    ]);
    await pumpApp(t, size: _se, scale: 2.0, prefs: {...spanishPrefs(), 'dw_threads': threads}, tab: AppTab.chat);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('chat-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('menu-history')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('history-delete-t1')));
    await t.pumpAndSettle();
    final text = find.byKey(const ValueKey('conversation-deleted-text'));
    expect(t.widget<WholeWordsText>(text).data, 'Conversación eliminada.');
    expect(wordProblems(t, text), isEmpty);
    expect(t.takeException(), isNull);
  });

  test('"con IA" keeps IA with its word in Spanish', () {
    final es = AppLocalizationsEs();
    expect(es.welcomeTitleAccent, 'con IA.');
    expect(es.coachesEyebrow, contains('con IA'));
  });

  group('review mode screen=chat-limit', () {
    test('the stand-in coach refuses with a paywall limit code', () async {
      final ai = ReviewMode.aiFor('chat-limit')!;
      Object? error;
      try {
        await ai.streamReply(history: const [], tier: SubscriptionTier.magnet, coach: Coaches.ava).drain<void>();
      } catch (e) {
        error = e;
      }
      expect(error, isA<CoachUnavailableException>());
      final code = (error! as CoachUnavailableException).code;
      expect(CoachLimitCode.paywallAction, contains(code));
      expect(ReviewMode.aiFor('chat-error'), isNotNull);
      expect(ReviewMode.aiFor('chat'), isNull);
    });

    testWidgets('the chat shows the limit notice and the paywall button', (t) async {
      setSurface(t, const Size(390, 844), 1);
      SharedPreferences.setMockInitialValues(onboardedPrefs());
      final storage = await StorageService.create();
      final store = FakeStoreService(entitled: true);
      final app = TestApp(AppState(storage: storage, ai: ReviewMode.aiFor('chat-limit')!, store: store), store, storage);
      await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat)));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('composer')), 'Give me a strong opener');
      await t.tap(find.byKey(const ValueKey('send')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('reply-failed')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('reply-failed-notice'))).data,
          AppLocalizationsEn().coachLimitRevoked);
      expect(find.byKey(const ValueKey('reply-paywall')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
