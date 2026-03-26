// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:terra_admin_app/main.dart';

void main() {
  testWidgets('TeraCard app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TeraCardApp());

    // Wait for splash screen animation
    await tester.pump(const Duration(seconds: 1));

    // Verify that the app launches successfully with splash screen
    expect(find.text('TeraCard'), findsOneWidget);
    expect(find.text('Staff App'), findsOneWidget);
  });
}
