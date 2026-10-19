import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ambulance_app/user_app/models/tracking.dart';
import 'package:ambulance_app/user_app/screens/live_tracking_screen.dart';
import 'package:ambulance_app/user_app/services/tracking_service.dart';

Map<String, dynamic> _json({bool ambulance = false, bool hospital = false}) => {
      'id': 42,
      'status': ambulance ? 'ambulance_assigned' : 'pending',
      'severity': 'critical',
      'emergency_type': 'Cardiac Arrest',
      'symptoms': ['chest pain'],
      'victims': 1,
      'department_needed': 'Cardiology',
      'transcript': 'Patient collapsed.',
      'location': {'lat': 8.52, 'lng': 76.943},
      'created_at': '2026-10-19T11:45:00Z',
      'assigned_hospital': hospital
          ? {
              'id': 3,
              'name': 'City General',
              'location': {'lat': 8.5241, 'lng': 76.9366},
            }
          : null,
      'ambulance': ambulance
          ? {
              'id': 7,
              'registration_number': 'KL-07-AE-1234',
              'vehicle_type': 'ALS',
              'location': {'lat': 8.5164, 'lng': 76.9491},
              'location_updated_at': '2026-10-19T11:46:00Z',
            }
          : null,
    };

class _FakeService extends TrackingService {
  _FakeService(this.data) : super();
  final Map<String, dynamic> data;

  @override
  Future<IncidentTracking> fetch(int incidentId) async =>
      IncidentTracking.fromJson(data);
}

void main() {
  group('IncidentTracking.fromJson', () {
    test('nothing assigned yet', () {
      final t = IncidentTracking.fromJson(_json());
      expect(t.ambulance, isNull);
      expect(t.assignedHospital, isNull);
      expect(t.location.latitude, 8.52);
      expect(t.isCompleted, isFalse);
    });

    test('ambulance and hospital', () {
      final t = IncidentTracking.fromJson(_json(ambulance: true, hospital: true));
      expect(t.ambulance!.registrationNumber, 'KL-07-AE-1234');
      expect(t.ambulance!.location!.longitude, 76.9491);
      expect(t.assignedHospital!.name, 'City General');
    });
  });

  group('LiveTrackingScreen', () {
    testWidgets('shows looking-for-ambulance while nothing is assigned',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LiveTrackingScreen(
            incidentId: 42, trackingService: _FakeService(_json())),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Looking for an ambulance…'), findsOneWidget);
      expect(find.text('#42'), findsOneWidget);
      expect(find.byTooltip('Recenter'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('shows the ambulance and hospital rows once assigned',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LiveTrackingScreen(
          incidentId: 42,
          trackingService:
              _FakeService(_json(ambulance: true, hospital: true)),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('KL-07-AE-1234'), findsOneWidget);
      expect(find.textContaining('City General'), findsOneWidget);
      expect(find.text('Ambulance → You'), findsOneWidget);
      expect(find.text('You → Hospital'), findsOneWidget);
    });
  });
}
