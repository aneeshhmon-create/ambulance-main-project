import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ambulance_user_app/main.dart';
import 'package:ambulance_user_app/models/user.dart';
import 'package:ambulance_user_app/services/user_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('New user without stored profile lands on RegisterScreen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AmbulanceUserApp());
    await tester.pumpAndSettle();

    // The AppBar title must be present
    expect(find.text('Emergency Ambulance'), findsOneWidget);

    // Registration UI elements must be present
    expect(find.text('Patient Registration'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Existing user with stored profile lands on HomeScreen',
      (WidgetTester tester) async {
    final storage = UserStorage();
    await storage.saveUser(const User(
      id: 1,
      name: 'Dr. Arjun',
      phone: '9876543210',
    ));

    await tester.pumpWidget(const AmbulanceUserApp());
    await tester.pumpAndSettle();

    // The AppBar title and user greeting must be present
    expect(find.text('Emergency Ambulance'), findsOneWidget);
    expect(find.text('Hi, Dr. Arjun'), findsOneWidget);

    // Primary emergency button must be present
    expect(find.text('Report Emergency'), findsOneWidget);

    // Switch user option must be present
    expect(find.text('Switch user'), findsOneWidget);
  });
}
