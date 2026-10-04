import 'package:flutter_test/flutter_test.dart';

import 'package:ambulance_user_app/main.dart';

void main() {
  testWidgets('App smoke test: title bar shows Emergency Ambulance',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AmbulanceUserApp());

    // The AppBar title must be present.
    expect(find.text('Emergency Ambulance'), findsOneWidget);

    // The primary action button must be present.
    expect(find.text('Test Connection'), findsOneWidget);
  });
}
