import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ambulance_app/user_app/main.dart';
import 'package:ambulance_app/driver_app/main.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('AmbulanceDriverApp renders AuthPage',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AmbulanceDriverApp());
    await tester.pumpAndSettle();

    expect(find.text('RapidAlert Driver'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('AmbulanceUserApp renders Registration on first launch',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AmbulanceUserApp());
    await tester.pumpAndSettle();

    expect(find.text('Emergency Ambulance'), findsOneWidget);
    expect(find.text('Patient Registration'), findsOneWidget);
  });
}
