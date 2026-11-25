import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/widgets/coach_text.dart';

String _shown(WidgetTester t) =>
    t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');

void main() {
  testWidgets('a ** without its partner (a reply still streaming) is not shown as text', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: CoachText('Pick one playful. **What'))));
    expect(_shown(t), contains('Pick one playful. What'));
    expect(_shown(t), isNot(contains('**')));
  });

  testWidgets('closed pairs are still bold, and the text around them is kept', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: CoachText('Try **this** first, then **that'))));
    final shown = _shown(t);
    expect(shown, contains('Try this first, then that'));
    expect(shown, isNot(contains('**')));
  });
}
