import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ambulance_app/user_app/config/routes.dart';
import 'package:ambulance_app/user_app/models/incident.dart';
import 'package:ambulance_app/user_app/models/user.dart';
import 'package:ambulance_app/driver_app/screens/driver_location_screen.dart';
import 'package:ambulance_app/user_app/screens/home_screen.dart';
import 'package:ambulance_app/user_app/screens/result_screen.dart';
import 'package:ambulance_app/user_app/screens/tracking_screen.dart';
import 'package:ambulance_app/user_app/services/api_service.dart';

void main() {
  group('Day 7 - TrackingScreen Integration', () {
    testWidgets('Renders status, stepper, emergency details, and hospital assignment',
        (WidgetTester tester) async {
      final mockData = {
        'id': 42,
        'status': 'hospital_assigned',
        'assigned_hospital_id': 12,
        'assigned_ambulance_id': 5,
        'emergency_type': 'Severe Trauma',
        'severity': 'critical',
        'department_needed': 'Trauma',
        'location': {'lat': 9.939, 'lng': 76.270},
        'victims': 2,
        'symptoms': ['Head injury', 'Bleeding'],
        'broadcasts': [
          {'id': 1, 'incident_id': 42, 'target_type': 'hospital', 'target_id': 12, 'status': 'accepted'}
        ],
      };

      final client = MockClient((request) async {
        return http.Response(jsonEncode(mockData), 200);
      });
      final api = ApiService(client: client);

      await tester.pumpWidget(MaterialApp(
        home: TrackingScreen(
          incidentId: 42,
          apiService: api,
        ),
      ));

      // Initially shows loading
      expect(find.text('Loading incident data...'), findsOneWidget);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Title in AppBar
      expect(find.text('Incident #42'), findsOneWidget);

      // Status card
      expect(find.text('HOSPITAL ASSIGNED'), findsOneWidget);

      // Stepper
      expect(find.text('PROGRESS'), findsOneWidget);
      expect(find.text('NOW'), findsOneWidget);

      // Emergency Details
      expect(find.text('EMERGENCY DETAILS'), findsOneWidget);
      expect(find.text('Severe trauma'), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('Trauma'), findsOneWidget);

      // Assignment info
      expect(find.text('ASSIGNMENT'), findsOneWidget);
      expect(find.text('#12'), findsOneWidget);
      expect(find.text('#5'), findsOneWidget);
    });

    testWidgets('Shows error view and retry button when initial fetch fails',
        (WidgetTester tester) async {
      final client = MockClient((request) async {
        return http.Response('Network timeout', 500);
      });
      final api = ApiService(client: client);

      await tester.pumpWidget(MaterialApp(
        home: TrackingScreen(
          incidentId: 99,
          apiService: api,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Day 7 - DriverLocationScreen Integration', () {
    testWidgets('Renders ID input, status badge, and start button',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DriverLocationScreen(),
      ));
      await tester.pump();

      expect(find.text('Driver Location'), findsOneWidget);
      expect(find.text('Live GPS sharing'), findsOneWidget);
      expect(find.text('AMBULANCE ID'), findsOneWidget);
      expect(find.text('Not sharing'), findsOneWidget);
      expect(find.text('CURRENT POSITION'), findsOneWidget);
      expect(find.text('Start Sharing Location'), findsOneWidget);
    });

    testWidgets('Validates empty ambulance ID with snackbar when starting',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DriverLocationScreen(),
      ));
      await tester.pump();

      final startBtn = find.text('Start Sharing Location');
      await tester.ensureVisible(startBtn);
      await tester.tap(startBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Please enter an ambulance ID first.'), findsOneWidget);
    });
  });

  group('Day 7 - Route Reachability', () {

    testWidgets('AppRoutes.tracking receives int incidentId and builds TrackingScreen',
        (WidgetTester tester) async {
      final mockData = {
        'id': 88,
        'status': 'completed',
        'location': {'lat': 9.9, 'lng': 76.2},
        'victims': 1,
        'broadcasts': [],
      };
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(mockData), 200);
      });
      final api = ApiService(client: mockClient);

      await tester.pumpWidget(MaterialApp(
        initialRoute: AppRoutes.result,
        routes: {
          AppRoutes.result: (context) => const ResultScreen(
                incident: Incident(
                  id: 88,
                  location: IncidentLocation(lat: 9.9, lng: 76.2),
                  status: 'completed',
                  emergencyType: 'Resolved',
                ),
              ),
          AppRoutes.tracking: (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            final incidentId = args is int ? args : 0;
            return TrackingScreen(
              incidentId: incidentId,
              apiService: api,
            );
          },
        },
      ));
      await tester.pumpAndSettle();

      final trackBtn = find.byKey(const ValueKey('track_my_request_button'));
      await tester.ensureVisible(trackBtn);
      await tester.pumpAndSettle();
      await tester.tap(trackBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Incident #88')),
        findsOneWidget,
      );
      expect(find.text('COMPLETED'), findsOneWidget);
    });
  });
}
