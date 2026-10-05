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

/// N2 regression (v1.11.0 review): a background `setState` rebuild of the
/// editor must not drop in-flight keystrokes.
///
/// The post editor feeds `BlockEditor.content` from `_contentController.text`,
/// which is updated by the controller's `onChanged`. If that callback is
/// debounced (the old P3-10 behaviour) the mirror lags `_lastEmitted` by up to
/// 100ms; a word-count timer that triggers a rebuild during that window passes
/// the stale text back in, `updateFromExternal` reparses it, and the freshly
/// typed characters vanish. With immediate content sync the mirror is always
/// current, so the rebuild hits the echo guard and keeps the text.
///
/// The test reproduces the lag deterministically: it edits the paragraph,
/// then forces a rebuild *without advancing time past the debounce window*.
/// On the old code the rebuild re-reads the still-stale mirror and loses the
/// edit; on the fixed code `onChanged` already propagated, so the text stays.
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

    // Type into the single paragraph text field.
    final tf = find.byType(TextField);
    await tester.enterText(tf, 'new');
    // At this point (old code) onChanged is still queued on a 100ms timer, so
    // `content` is still '<p>old</p>'. The fix fires it synchronously.

    // Force a rebuild that re-reads `content` — no extra time is advanced, so
    // the old 100ms timer has NOT fired and still holds the stale mirror.
    await tester.pumpWidget(build());

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, 'new');
  });

  testWidgets('editing then echoing the same content does not reset focus (N2)',
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
    await tester.enterText(find.byType(TextField), 'second');
    // Now content mirrors the edit synchronously (fix). A rebuild that echoes
    // it back must NOT reparse/reset anything.
    await tester.pumpWidget(build());
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, 'second');
  });
}
