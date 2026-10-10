// Smoke test for the User App entry point.
// Verifies that UserApp renders without throwing.

import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_app/user_app/main.dart';

void main() {
  testWidgets('UserApp smoke test — renders without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(const UserApp());
    // TestHarnessScreen should be present.
    expect(find.text('Tracking Screen — Test Harness'), findsOneWidget);
  });
}
