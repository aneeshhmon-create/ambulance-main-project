import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ambulance_user_app/config/routes.dart';
import 'package:ambulance_user_app/models/incident.dart';
import 'package:ambulance_user_app/screens/result_screen.dart';

void main() {
  Widget buildTestWidget({
    Incident? incident,
    Future<void> Function()? onCall108,
    void Function(Object? trackingArg)? onTracked,
    void Function()? onDone,
  }) {
    return MaterialApp(
      initialRoute: AppRoutes.result,
      routes: {
        AppRoutes.root: (context) {
          onDone?.call();
          return const Scaffold(body: Text('Home Screen'));
        },
        AppRoutes.result: (context) => ResultScreen(
              incident: incident,
              onCall108: onCall108,
            ),
        AppRoutes.tracking: (context) {
          final arg = ModalRoute.of(context)?.settings.arguments;
          onTracked?.call(arg);
          return Scaffold(body: Text('Tracking Screen: $arg'));
        },
      },
    );
  }

  group('ResultScreen - Core Layout & Display', () {
    testWidgets('Renders header, severity badge, summary card, and Malayalam transcript',
        (WidgetTester tester) async {
      const incident = Incident(
        id: 101,
        userId: 1,
        location: IncidentLocation(lat: 9.9312, lng: 76.2673),
        emergencyType: 'Road Accident',
        severity: 'critical',
        symptoms: ['Chest pain', 'Severe bleeding', 'Head injury'],
        victims: 2,
        departmentNeeded: 'Trauma & Orthopaedics',
        status: 'pending',
        broadcasts: [
          Broadcast(id: 1, incidentId: 101, targetType: 'hospital', targetId: 10, status: 'sent'),
          Broadcast(id: 2, incidentId: 101, targetType: 'hospital', targetId: 11, status: 'sent'),
        ],
        transcript: 'എനിക്ക് നെഞ്ചുവേദനയുണ്ട്, please send an ambulance quickly!',
      );

      await tester.pumpWidget(buildTestWidget(incident: incident));
      await tester.pumpAndSettle();

      // Header
      expect(find.text('We understood your report'), findsOneWidget);
      expect(find.text('Incident #101'), findsOneWidget);

      // Severity badge
      expect(find.text('CRITICAL SEVERITY'), findsOneWidget);

      // Summary card
      expect(find.text('Emergency Type'), findsOneWidget);
      expect(find.text('Road Accident'), findsOneWidget);
      expect(find.text('Department Needed'), findsOneWidget);
      expect(find.text('Trauma & Orthopaedics'), findsOneWidget);
      expect(find.text('Victims'), findsOneWidget);
      expect(find.text('2 people'), findsOneWidget);

      // Symptoms chips
      expect(find.text('Identified Symptoms'), findsOneWidget);
      expect(find.text('Chest pain'), findsOneWidget);
      expect(find.text('Severe bleeding'), findsOneWidget);
      expect(find.text('Head injury'), findsOneWidget);

      // Transcript with mixed Malayalam & English
      expect(find.text('What we heard'), findsOneWidget);
      expect(find.text('എനിക്ക് നെഞ്ചുവേദനയുണ്ട്, please send an ambulance quickly!'), findsOneWidget);

      // Status line
      expect(find.text('Waiting for a hospital to accept'), findsOneWidget);

      // Hospitals count
      expect(find.text('2 hospitals notified'), findsOneWidget);

      // Action buttons
      expect(find.text('Track my request'), findsOneWidget);
      expect(find.text('Call 108'), findsOneWidget);
    });

    testWidgets('Renders color-coded severity badges for low, medium, and high',
        (WidgetTester tester) async {
      const severities = ['low', 'medium', 'high'];
      final expectedLabels = ['LOW SEVERITY', 'MEDIUM SEVERITY', 'HIGH SEVERITY'];

      for (var i = 0; i < severities.length; i++) {
        final incident = Incident(
          id: 200 + i,
          location: const IncidentLocation(lat: 9.9, lng: 76.2),
          emergencyType: 'Medical Emergency',
          severity: severities[i],
          status: 'pending',
          broadcasts: const [
            Broadcast(id: 1, incidentId: 200, targetType: 'hospital', targetId: 5, status: 'sent'),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: ResultScreen(incident: incident),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(expectedLabels[i]), findsOneWidget);
      }
    });

    testWidgets('Hides symptoms section when symptoms list is empty',
        (WidgetTester tester) async {
      const incident = Incident(
        id: 102,
        location: IncidentLocation(lat: 9.9, lng: 76.2),
        emergencyType: 'Cardiac Emergency',
        severity: 'high',
        symptoms: [],
        status: 'pending',
      );

      await tester.pumpWidget(buildTestWidget(incident: incident));
      await tester.pumpAndSettle();

      expect(find.text('Identified Symptoms'), findsNothing);
    });

    testWidgets('Maps incident status correctly into plain words',
        (WidgetTester tester) async {
      const statusMap = {
        'pending': 'Waiting for a hospital to accept',
        'hospital_assigned': 'Hospital found',
        'ambulance_assigned': 'Ambulance on the way',
        'completed': 'Incident resolved',
      };

      for (final entry in statusMap.entries) {
        final incident = Incident(
          id: 300,
          location: const IncidentLocation(lat: 9.9, lng: 76.2),
          emergencyType: 'Asthma Attack',
          severity: 'medium',
          status: entry.key,
        );

        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: ResultScreen(incident: incident),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget);
      }
    });
  });

  group('ResultScreen - Edge Cases', () {
    testWidgets('Fallback extraction: shows neutral notice and avoids misleading severity',
        (WidgetTester tester) async {
      const incident = Incident(
        id: 401,
        location: IncidentLocation(lat: 9.9, lng: 76.2),
        emergencyType: 'unspecified',
        severity: 'medium',
        status: 'pending',
      );

      await tester.pumpWidget(buildTestWidget(incident: incident));
      await tester.pumpAndSettle();

      // Neutral notice present
      expect(
        find.text("We couldn't fully analyse your message, but help is still being arranged"),
        findsOneWidget,
      );

      // Does NOT show "MEDIUM SEVERITY" badge
      expect(find.text('MEDIUM SEVERITY'), findsNothing);
    });

    testWidgets('Zero hospitals: shows warning banner and prominent Call 108 button',
        (WidgetTester tester) async {
      const incident = Incident(
        id: 402,
        location: IncidentLocation(lat: 9.9, lng: 76.2),
        emergencyType: 'Allergic Reaction',
        severity: 'high',
        status: 'pending',
        broadcasts: [], // Zero hospitals
      );

      await tester.pumpWidget(buildTestWidget(incident: incident));
      await tester.pumpAndSettle();

      // Does not show a cheerful count
      expect(find.text('0 hospitals notified'), findsNothing);

      // Warning banner
      expect(find.text('No nearby hospital found yet'), findsOneWidget);

      // Call 108 prominent button
      expect(find.text('Call 108 Now'), findsOneWidget);
    });

    testWidgets('Empty/null transcript: shows "No transcript available"',
        (WidgetTester tester) async {
      const incident = Incident(
        id: 403,
        location: IncidentLocation(lat: 9.9, lng: 76.2),
        emergencyType: 'Fever',
        severity: 'low',
        status: 'pending',
        transcript: null,
      );

      await tester.pumpWidget(buildTestWidget(incident: incident));
      await tester.pumpAndSettle();

      expect(find.text('No transcript available'), findsOneWidget);
    });

    testWidgets('Missing/null fields do not crash the page',
        (WidgetTester tester) async {
      const incident = Incident(
        id: 404,
        location: IncidentLocation(lat: 0.0, lng: 0.0),
        emergencyType: null,
        severity: null,
        departmentNeeded: null,
        victims: 1,
        status: 'pending',
        transcript: '',
      );

      await tester.pumpWidget(buildTestWidget(incident: incident));
      await tester.pumpAndSettle();

      expect(find.text('We understood your report'), findsOneWidget);
      expect(find.text('Incident #404'), findsOneWidget);
    });
  });

  group('ResultScreen - Navigation & Actions', () {
    testWidgets('Track my request button navigates to /tracking with incident.id as int',
        (WidgetTester tester) async {
      Object? receivedArg;
      const incident = Incident(
        id: 777,
        location: IncidentLocation(lat: 9.9, lng: 76.2),
        emergencyType: 'Stroke',
        severity: 'critical',
        status: 'pending',
      );

      await tester.pumpWidget(buildTestWidget(
        incident: incident,
        onTracked: (arg) => receivedArg = arg,
      ));
      await tester.pumpAndSettle();

      final trackBtn = find.byKey(const ValueKey('track_my_request_button'));
      await tester.ensureVisible(trackBtn);
      await tester.pumpAndSettle();
      await tester.tap(trackBtn);
      await tester.pumpAndSettle();

      expect(receivedArg, 777);
      expect(receivedArg is int, isTrue);
      expect(find.text('Tracking Screen: 777'), findsOneWidget);
    });

    testWidgets('Call 108 button triggers onCall108 callback',
        (WidgetTester tester) async {
      var call108Invoked = false;
      const incident = Incident(
        id: 888,
        location: IncidentLocation(lat: 9.9, lng: 76.2),
        emergencyType: 'Burn',
        severity: 'high',
        status: 'pending',
      );

      await tester.pumpWidget(buildTestWidget(
        incident: incident,
        onCall108: () async => call108Invoked = true,
      ));
      await tester.pumpAndSettle();

      final callBtn = find.byKey(const ValueKey('call_108_button'));
      await tester.ensureVisible(callBtn);
      await tester.pumpAndSettle();
      await tester.tap(callBtn);
      await tester.pumpAndSettle();

      expect(call108Invoked, isTrue);
    });

    testWidgets('Done action in AppBar returns to Home',
        (WidgetTester tester) async {
      var returnedHome = false;
      const incident = Incident(
        id: 999,
        location: IncidentLocation(lat: 9.9, lng: 76.2),
        emergencyType: 'Accident',
        severity: 'medium',
        status: 'pending',
      );

      await tester.pumpWidget(buildTestWidget(
        incident: incident,
        onDone: () => returnedHome = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(returnedHome, isTrue);
      expect(find.text('Home Screen'), findsOneWidget);
    });
  });
}
