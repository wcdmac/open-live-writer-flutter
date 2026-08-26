import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_live_writer/main.dart';

void main() {
  testWidgets('App renders the account onboarding screen',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OpenLiveWriterApp());
    await tester.pumpAndSettle();

    // First-time users land on the add-account wizard.
    expect(find.text('Open Live Writer'), findsOneWidget);
    expect(find.text('Blog homepage URL'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Detect blog settings'), findsOneWidget);
  });
}
