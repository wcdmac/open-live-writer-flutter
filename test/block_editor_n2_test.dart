import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/editor/block_editor.dart';
import 'package:open_live_writer/l10n/app_localizations.dart';

/// Minimal MaterialApp carrying the app's localization delegates so widgets
/// that call [AppLocalizations.of] render in tests without a real shell.
Widget _testApp(Widget home) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

/// N2 regression (v1.11.0 review): a background rebuild of the editor that
/// feeds a *stale* content mirror must not drop in-flight keystrokes.
///
/// The post editor binds `BlockEditor.content` to `_contentController.text`,
/// which is updated only by the controller's `onChanged`. With the old P3-10
/// 100ms debounce, `onChanged` lagged `_lastEmitted` by up to 100ms; a
/// word-count `setState` rebuild during that window passed the stale mirror
/// back in, `updateFromExternal` reparsed it (it differed from `_lastEmitted`)
/// and the freshly typed characters vanished. The fix fires `onChanged`
/// immediately, so the mirror is always current and the rebuild hits the echo
/// guard and keeps the text.
///
/// Each test taps the paragraph to enter edit mode (a block shows a read-only
/// `HtmlWidget` until focused, so no `TextField` exists before the tap), edits
/// it, then forces a rebuild *without advancing the debounce timer* — the
/// deterministic way to expose the old lag. On the old code the mirror is
/// still stale at that point and the edit is lost; on the fixed code it sticks.
void main() {
  testWidgets(
      'rebuild during debounce window keeps the in-flight edit (N2)',
      (WidgetTester tester) async {
    // The parent's content mirror, updated only by onContentChanged — exactly
    // like post_editor_page's `_contentController` driven by the editor.
    var content = '<p>old</p>';

    Widget build() => _testApp(
          Scaffold(
            body: BlockEditor(
              content: content,
              onContentChanged: (html) => content = html,
            ),
          ),
        );

    await tester.pumpWidget(build());

    // Enter edit mode: tap the (unfocused, read-only) paragraph card.
    final card = find.byWidgetPredicate((w) => w is InkWell);
    await tester.tap(card.first);
    await tester.pump();

    // Type into the now-visible paragraph text field.
    final tf = find.byType(TextField);
    expect(tf, findsOneWidget);
    await tester.enterText(tf, 'new');
    await tester.pump();

    // Force a rebuild that re-reads `content` — no timer is advanced, so on the
    // old debounced code `content` is still '<p>old</p>' and the edit is lost;
    // on the fixed code `onChanged` already fired and the text sticks.
    await tester.pumpWidget(build());
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, 'new');
  });

  testWidgets('editing then echoing the emitted content keeps the text (N2)',
      (WidgetTester tester) async {
    var content = '<p>first</p>';
    Widget build() => _testApp(
          Scaffold(
            body: BlockEditor(
              content: content,
              onContentChanged: (html) => content = html,
            ),
          ),
        );
    await tester.pumpWidget(build());
    await tester.tap(find.byWidgetPredicate((w) => w is InkWell).first);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump();

    // Mirror is now current (fixed code fires onChanged immediately). A rebuild
    // that echoes the emitted content back must NOT reparse and lose it.
    expect(content, '<p>second</p>');
    await tester.pumpWidget(build());
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, 'second');
  });
}
