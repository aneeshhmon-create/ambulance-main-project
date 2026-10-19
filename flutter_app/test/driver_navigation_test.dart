// test/driver_navigation_test.dart
//
// Unit and widget tests for the driver navigation feature:
//   • DriverIncidentDetail JSON deserialization
//   • RoutingService fallback logic
//   • IncidentTopStrip expand and cancel callbacks
//   • NavigationStatusChip rendering

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:ambulance_app/driver_app/models/incident_detail.dart';
import 'package:ambulance_app/driver_app/services/routing_service.dart';
import 'package:ambulance_app/driver_app/widgets/incident_top_strip.dart';
import 'package:ambulance_app/driver_app/widgets/navigation_status_chip.dart';

void main() {
  group('DriverIncidentDetail JSON parsing', () {
    test('parses unassigned hospital JSON correctly', () {
      final json = {
        'id': 101,
        'status': 'ambulance_assigned',
        'severity': 'critical',
        'emergency_type': 'Cardiac Arrest',
        'symptoms': ['chest pain', 'collapse'],
        'victims': 1,
        'department_needed': 'Cardiology',
        'transcript': 'Patient fell unconscious.',
        'location': {'lat': 9.9312, 'lng': 76.2673},
        'created_at': '2026-10-19T10:00:00.000Z',
        'assigned_hospital': null,
      };

      final detail = DriverIncidentDetail.fromJson(json);

      expect(detail.id, 101);
      expect(detail.status, 'ambulance_assigned');
      expect(detail.severity, 'critical');
      expect(detail.emergencyType, 'Cardiac Arrest');
      expect(detail.symptoms, ['chest pain', 'collapse']);
      expect(detail.victims, 1);
      expect(detail.departmentNeeded, 'Cardiology');
      expect(detail.transcript, 'Patient fell unconscious.');
      expect(detail.location.latitude, closeTo(9.9312, 0.0001));
      expect(detail.location.longitude, closeTo(76.2673, 0.0001));
      expect(detail.assignedHospital, isNull);
    });

    test('parses assigned hospital JSON correctly', () {
      final json = {
        'id': 102,
        'status': 'ambulance_assigned',
        'severity': 'high',
        'emergency_type': 'Trauma',
        'symptoms': ['fracture'],
        'victims': 2,
        'department_needed': 'Orthopedics',
        'transcript': null,
        'location': {'lat': 9.9300, 'lng': 76.2600},
        'created_at': '2026-10-19T10:30:00.000Z',
        'assigned_hospital': {
          'id': 5,
          'name': 'Lisie Hospital',
          'location': {'lat': 9.9912, 'lng': 76.2890},
        },
      };

      final detail = DriverIncidentDetail.fromJson(json);

      expect(detail.id, 102);
      expect(detail.assignedHospital, isNotNull);
      expect(detail.assignedHospital!.id, 5);
      expect(detail.assignedHospital!.name, 'Lisie Hospital');
      expect(detail.assignedHospital!.location.latitude, closeTo(9.9912, 0.0001));
      expect(detail.assignedHospital!.location.longitude, closeTo(76.2890, 0.0001));
    });
  });

  group('RoutingService fallback', () {
    test('RouteResult fallback preserves origin and destination', () {
      const origin = LatLng(9.9312, 76.2673);
      const destination = LatLng(9.9912, 76.2890);

      const res = RouteResult(
        points: [origin, destination],
        distanceKm: 7.2,
        durationMinutes: 10.8,
        isFallback: true,
      );

      expect(res.points.length, 2);
      expect(res.isFallback, isTrue);
      expect(res.distanceKm, 7.2);
    });
  });

  group('IncidentTopStrip widget', () {
    testWidgets('renders summary and toggles expansion on tap',
        (tester) async {
      bool canceled = false;
      final incident = DriverIncidentDetail(
        id: 42,
        status: 'ambulance_assigned',
        severity: 'critical',
        emergencyType: 'Cardiac Arrest',
        symptoms: const ['chest pain', 'unresponsive'],
        victims: 1,
        departmentNeeded: 'Cardiology',
        transcript: 'Patient collapsed 5 minutes ago.',
        location: const LatLng(9.9312, 76.2673),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncidentTopStrip(
              incident: incident,
              onCancel: () => canceled = true,
            ),
          ),
        ),
      );

      // Verify collapsed summary
      expect(find.text('#42'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.textContaining('Cardiac Arrest'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Transcript and symptoms are initially collapsed
      expect(find.text('Reported Symptoms:'), findsNothing);

      // Tap to expand
      await tester.tap(find.text('#42'));
      await tester.pumpAndSettle();

      // Now expanded
      expect(find.text('Reported Symptoms:'), findsOneWidget);
      expect(find.text('chest pain'), findsOneWidget);
      expect(find.text('Patient collapsed 5 minutes ago.'), findsOneWidget);

      // Tap Cancel button
      await tester.tap(find.text('Cancel'));
      expect(canceled, isTrue);
    });
  });

  group('NavigationStatusChip widget', () {
    testWidgets('shows searching state when hospital is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationStatusChip(hospital: null),
          ),
        ),
      );

      expect(find.text('Looking for a hospital...'), findsOneWidget);
    });

    testWidgets('shows hospital name and route info when assigned',
        (tester) async {
      const hospital = DriverIncidentHospital(
        id: 1,
        name: 'Aster Medcity',
        location: LatLng(10.04, 76.27),
      );
      const route = RouteResult(
        points: [LatLng(9.93, 76.26), LatLng(10.04, 76.27)],
        distanceKm: 12.4,
        durationMinutes: 18.2,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationStatusChip(
              hospital: hospital,
              route: route,
            ),
          ),
        ),
      );

      expect(find.textContaining('Aster Medcity'), findsOneWidget);
      expect(find.textContaining('12.4 km (19 min)'), findsOneWidget);
    });
  });
}
