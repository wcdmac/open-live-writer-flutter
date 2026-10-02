import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_live_writer/l10n/app_localizations.dart';
import 'package:open_live_writer/models/blog.dart';
import 'package:open_live_writer/models/blog_post.dart';
import 'package:open_live_writer/state/app_state.dart';
import 'package:open_live_writer/views/add_account_page.dart';
import 'package:open_live_writer/views/home_page.dart';
import 'package:open_live_writer/editor/block_editor.dart';

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

BlogAccount _fakeAccount() => BlogAccount(
      id: 'acct-1',
      blogId: '1',
      name: 'Test Blog',
      homepageUrl: 'https://example.com',
      apiUrl: 'https://example.com/wp-json',
      protocol: BlogProtocol.rest,
      username: 'tester',
    );

BlogPost _fakePost(String id, String title) => BlogPost(
      id: id,
      title: title,
      status: PostStatus.publish,
      content: '<p>$title</p>',
      datePublished: DateTime(2026, 1, 1),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HomePage smoke (no network)', () {
    testWidgets('renders the dashboard post list for a local account',
        (WidgetTester tester) async {
      final app = AppState();
      app.accounts = [_fakeAccount()];
      app.currentAccount = app.accounts.first;
      app.posts = [
        _fakePost('p1', 'First post'),
        _fakePost('p2', 'Second post'),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: _testApp(const HomePage()),
        ),
      );
      await tester.pumpAndSettle();

      // Title and excerpt (derived from the same content) both render the
      // title text, so assert presence rather than a single occurrence.
      expect(find.text('First post'), findsWidgets);
      expect(find.text('Second post'), findsWidgets);
      // No account switcher text leaking into the body; app bar shows name.
      expect(find.text('Test Blog'), findsWidgets);
    });

    testWidgets('shows the "load more" footer when more posts exist (P1-5)',
        (WidgetTester tester) async {
      final app = AppState();
      app.accounts = [_fakeAccount()];
      app.currentAccount = app.accounts.first;
      app.posts = [_fakePost('p1', 'Only post')];
      app.canLoadMore = true;
      app.loadingMore = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: _testApp(const HomePage()),
        ),
      );
      await tester.pumpAndSettle();

      // Footer is the trailing list item when canLoadMore is true.
      expect(find.text('Load more'), findsOneWidget);
    });

    testWidgets('footer shows a spinner while the next page loads (P1-5)',
        (WidgetTester tester) async {
      final app = AppState();
      app.accounts = [_fakeAccount()];
      app.currentAccount = app.accounts.first;
      app.posts = [_fakePost('p1', 'Only post')];
      app.canLoadMore = true;
      app.loadingMore = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: _testApp(const HomePage()),
        ),
      );
      // An indeterminate CircularProgressIndicator never "settles", so pump a
      // single frame and assert the spinner is in the tree rather than
      // calling pumpAndSettle (which would time out).
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });
  });

  group('Login / blog-management navigation (no network)', () {
    testWidgets('shows the embedded AddAccountPage when no account exists',
        (WidgetTester tester) async {
      final app = AppState(); // no accounts, no currentAccount

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: _testApp(const HomePage()),
        ),
      );
      await tester.pumpAndSettle();

      // With no account the dashboard is replaced by the embedded login wizard.
      expect(find.byType(AddAccountPage), findsOneWidget);
    });

    testWidgets(
        'swaps AddAccountPage for the dashboard once an account is added',
        (WidgetTester tester) async {
      final app = AppState(); // start on the embedded login screen

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: _testApp(const HomePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddAccountPage), findsOneWidget);

      // Simulate a successful addAccount() flip (what _finish() triggers):
      // hasAccount goes true and the Selector rebuilds the home screen.
      app.accounts = [_fakeAccount()];
      app.currentAccount = app.accounts.first;
      app.notifyListeners();
      await tester.pumpAndSettle();

      // The login wizard must be gone and the dashboard must be showing.
      expect(find.byType(AddAccountPage), findsNothing);
      expect(find.text('Test Blog'), findsWidgets);
    });
  });

  group('BlockEditor smoke (no network)', () {
    testWidgets('renders parsed block content', (WidgetTester tester) async {
      await tester.pumpWidget(_testApp(Scaffold(
        body: BlockEditor(
          content: '<!-- wp:paragraph --><p>Hello world</p><!-- /wp:paragraph -->',
          onContentChanged: (_) {},
        ),
      )));
      await tester.pumpAndSettle();
      // The paragraph renders as WYSIWYG HTML (a RichText), not a plain Text
      // widget, so search RichText too via findRichText.
      expect(find.text('Hello world', findRichText: true), findsWidgets);
    });

    testWidgets('shows the empty hint for blank content',
        (WidgetTester tester) async {
      await tester.pumpWidget(_testApp(Scaffold(
        body: BlockEditor(content: '', onContentChanged: (_) {}),
      )));
      await tester.pumpAndSettle();
      // Resolve the localized hint from the live context so the assertion is
      // locale-independent (no hard-coded ellipsis character).
      final l10n = AppLocalizations.of(
          tester.element(find.byType(BlockEditor)))!;
      expect(find.text(l10n.emptyBlockHint), findsOneWidget);
    });
  });
}
