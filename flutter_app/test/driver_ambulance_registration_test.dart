import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ambulance_app/driver_app/screens/add_ambulance_screen.dart';
import 'package:ambulance_app/driver_app/utils/validators.dart';
import 'package:ambulance_app/driver_app/widgets/ambulance_type_selector.dart';

void main() {
  group('Validators.validateRegistrationNumber', () {
    test('accepts plates with spaces, hyphens and lower case', () {
      expect(Validators.validateRegistrationNumber('KL 07 AB 1234'), isNull);
      expect(Validators.validateRegistrationNumber('kl-07-ab-1234'), isNull);
      expect(Validators.validateRegistrationNumber('KL07AB1234'), isNull);
    });

    test('rejects empty, too short and symbol-only input', () {
      expect(Validators.validateRegistrationNumber(''), isNotNull);
      expect(Validators.validateRegistrationNumber(null), isNotNull);
      expect(Validators.validateRegistrationNumber('K7'), isNotNull);
      expect(Validators.validateRegistrationNumber('??##!!'), isNotNull);
    });
  });

  group('AmbulanceTypes', () {
    test('values match what the server accepts', () {
      expect(AmbulanceTypes.als, 'ALS');
      expect(AmbulanceTypes.bls, 'BLS');
      expect(AmbulanceTypes.both, 'ALS+BLS');
    });

    test('labels', () {
      expect(AmbulanceTypes.label('ALS+BLS'), 'ALS + BLS');
      expect(AmbulanceTypes.label(null), 'Standard');
      expect(AmbulanceTypes.shortLabel('ALS+BLS'), 'ALS + BLS');
      expect(AmbulanceTypes.shortLabel('BLS'), 'BLS');
    });
  });

  group('AddAmbulanceScreen', () {
    testWidgets('submitting empty shows both field errors', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AddAmbulanceScreen()));

      await tester.tap(find.widgetWithText(FilledButton, 'Add ambulance'));
      await tester.pump();

      expect(find.text('Registration number is required'), findsOneWidget);
      expect(find.text('Choose ALS, BLS or Both'), findsOneWidget);
    });

    testWidgets('offers ALS, BLS and Both', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AddAmbulanceScreen()));

      expect(find.text('ALS'), findsOneWidget);
      expect(find.text('BLS'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
    });

    testWidgets('picking a type clears the type error', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AddAmbulanceScreen()));
      await tester.tap(find.widgetWithText(FilledButton, 'Add ambulance'));
      await tester.pump();

      await tester.tap(find.text('Both'));
      await tester.pump();

      expect(find.text('Choose ALS, BLS or Both'), findsNothing);
    });
  });
}
