import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ambulance_app/user_app/main.dart';
import 'package:ambulance_app/driver_app/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AmbulanceDriverApp renders DriverLocationScreen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AmbulanceDriverApp());
    await tester.pump();

    expect(find.text('Driver Location'), findsOneWidget);
    expect(find.text('Start Sharing Location'), findsOneWidget);
  });

  testWidgets('AmbulanceUserApp renders Registration on first launch',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AmbulanceUserApp());
    await tester.pumpAndSettle();

    expect(find.text('Emergency Ambulance'), findsOneWidget);
    expect(find.text('Patient Registration'), findsOneWidget);
  });
}
