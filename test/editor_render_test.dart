import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_live_writer/l10n/app_localizations.dart';
import 'package:open_live_writer/models/blog_post.dart';
import 'package:open_live_writer/state/app_state.dart';
import 'package:open_live_writer/views/post_editor_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reproduces the "title renders, content blank" report: pumps the real
/// PostEditorPage at phone width with a loaded post and inspects the
/// RenderEditable of the content field — size, position and paint bounds.
void main() {
  testWidgets('content EditableText has non-zero size and on-screen position',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.reset);

    final app = AppState();
    const content =
        '<!-- wp:paragraph -->\n<p>欢迎使用 WordPress。这是您的第一篇文章。编辑或删除它，然后开始写作吧！</p>\n<!-- /wp:paragraph -->';
    final post = BlogPost(
      id: '1',
      title: '世界，您好！',
      content: content,
      status: PostStatus.publish,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1E6FD9),
                brightness: Brightness.light),
            useMaterial3: true,
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          home: PostEditorPage(existingPost: post),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Report any build exception (e.g. TabBar without a controller).
    final exception = tester.takeException();
    debugPrint('BUILD EXCEPTION: $exception');

    final editables =
        tester.widgetList<EditableText>(find.byType(EditableText)).toList();
    debugPrint('editable count: ${editables.length}');
    for (final e in editables) {
      debugPrint(
          'editable: textLen=${e.controller.text.length} expands=${e.expands} maxLines=${e.maxLines}');
    }

    final boxes = tester.renderObjectList<RenderBox>(
        find.byType(EditableText)).toList();
    for (final b in boxes) {
      final pos = b.localToGlobal(Offset.zero);
      debugPrint(
          'EditableText box: size=${b.size} pos=$pos paintBounds=${b.paintBounds}');
    }

    // The content field must render with real size inside the viewport.
    // Regression: the TabBar used to build without a TabController, which
    // killed the whole editor pane on phone widths (blank content).
    expect(boxes.length, 2, reason: 'title + content fields');
    final contentBox = boxes.last; // expands:true content field
    expect(contentBox.size.width, greaterThan(300));
    expect(contentBox.size.height, greaterThan(30));
    expect(contentBox.localToGlobal(Offset.zero).dy, inInclusiveRange(0, 800));

    expect(tester.takeException(), isNull);
  });
}
