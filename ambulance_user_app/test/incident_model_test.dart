import 'package:flutter_test/flutter_test.dart';

import 'package:ambulance_user_app/models/incident.dart';

void main() {
  group('Incident.fromJson — full backend response', () {
    test('parses all fields from full FastAPI IncidentOut response', () {
      final json = {
        'id': 101,
        'user_id': 5,
        'location': {
          'lat': 9.9312,
          'lng': 76.2673,
        },
        'emergency_type': 'accident',
        'severity': 'critical',
        'symptoms': ['heavy bleeding', 'unconscious'],
        'victims': 2,
        'department_needed': 'Trauma',
        'status': 'pending',
        'assigned_hospital_id': null,
        'assigned_ambulance_id': 12,
        'created_at': '2026-10-08T15:30:00.000Z',
        'broadcasts': [
          {
            'id': 1,
            'incident_id': 101,
            'target_type': 'hospital',
            'target_id': 4,
            'status': 'pending',
            'sent_at': '2026-10-08T15:30:00.000Z',
            'responded_at': null,
          },
          {
            'id': 2,
            'incident_id': 101,
            'target_type': 'hospital',
            'target_id': 7,
            'status': 'pending',
            'sent_at': '2026-10-08T15:30:00.000Z',
            'responded_at': null,
          }
        ],
        'assigned_ambulance': {
          'id': 12,
          'driver_name': 'Kavya',
          'driver_phone': '9876543210',
          'location': {
            'lat': 9.9350,
            'lng': 76.2700,
          },
          'is_available': false,
        },
        'transcript': 'Two people injured in a car crash near Aluva.',
        'extracted_data': {
          'emergency_type': 'accident',
          'severity': 'critical',
          'symptoms': ['heavy bleeding', 'unconscious'],
          'victims': 2,
          'department_needed': 'Trauma',
        },
      };

      final incident = Incident.fromJson(json);

      expect(incident.id, 101);
      expect(incident.userId, 5);
      expect(incident.location.lat, 9.9312);
      expect(incident.location.lng, 76.2673);
      expect(incident.emergencyType, 'accident');
      expect(incident.severity, 'critical');
      expect(incident.symptoms, ['heavy bleeding', 'unconscious']);
      expect(incident.victims, 2);
      expect(incident.departmentNeeded, 'Trauma');
      expect(incident.status, 'pending');
      expect(incident.assignedHospitalId, isNull);
      expect(incident.assignedAmbulanceId, 12);
      expect(incident.createdAt, isNotNull);
      expect(incident.broadcasts.length, 2);
      expect(incident.broadcasts.first.targetId, 4);
      expect(incident.assignedAmbulance?.driverName, 'Kavya');
      expect(incident.assignedAmbulance?.driverPhone, '9876543210');
      expect(incident.assignedAmbulance?.isAvailable, isFalse);
      expect(incident.transcript, contains('car crash near Aluva'));
      expect(incident.extractedData?['emergency_type'], 'accident');
    });
  });

  group('Incident.fromJson — fallback extraction response', () {
    test('parses fallback extraction without throwing', () {
      final json = {
        'id': 102,
        'user_id': null,
        'location': {
          'lat': 9.9312,
          'lng': 76.2673,
        },
        'emergency_type': 'unspecified',
        'severity': 'medium',
        'symptoms': [],
        'victims': 1,
        'department_needed': 'General Medicine',
        'status': 'pending',
        'assigned_hospital_id': null,
        'assigned_ambulance_id': null,
        'created_at': '2026-10-08T15:35:00.000Z',
        'broadcasts': [],
        'assigned_ambulance': null,
        'transcript': '',
        'extracted_data': {
          'emergency_type': 'unspecified',
          'severity': 'medium',
          'symptoms': [],
          'victims': 1,
          'department_needed': 'General Medicine',
        },
      };

      final incident = Incident.fromJson(json);

      expect(incident.id, 102);
      expect(incident.userId, isNull);
      expect(incident.emergencyType, 'unspecified');
      expect(incident.severity, 'medium');
      expect(incident.symptoms, isEmpty);
      expect(incident.victims, 1);
      expect(incident.departmentNeeded, 'General Medicine');
      expect(incident.assignedAmbulance, isNull);
      expect(incident.broadcasts, isEmpty);
      expect(incident.transcript, isEmpty);
    });

    test('handles completely empty JSON gracefully', () {
      final incident = Incident.fromJson({});

      expect(incident.id, 0);
      expect(incident.userId, isNull);
      expect(incident.location.lat, 0.0);
      expect(incident.location.lng, 0.0);
      expect(incident.symptoms, isEmpty);
      expect(incident.victims, 1);
      expect(incident.status, 'pending');
      expect(incident.broadcasts, isEmpty);
      expect(incident.assignedAmbulance, isNull);
      expect(incident.extractedData, isNull);
    });
  });
}
