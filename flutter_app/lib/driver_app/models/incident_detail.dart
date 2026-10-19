// lib/driver_app/models/incident_detail.dart
//
// Model representing the full incident details returned to an authenticated driver:
// GET /ambulances/{ambulance_id}/incidents/{incident_id}

import 'package:latlong2/latlong.dart';

class DriverIncidentHospital {
  final int id;
  final String name;
  final LatLng location;

  const DriverIncidentHospital({
    required this.id,
    required this.name,
    required this.location,
  });

  factory DriverIncidentHospital.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>;
    return DriverIncidentHospital(
      id: j['id'] as int,
      name: j['name'] as String,
      location: LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      ),
    );
  }
}

class DriverIncidentDetail {
  final int id;
  final String status;
  final String? severity;
  final String? emergencyType;
  final List<String> symptoms;
  final int victims;
  final String? departmentNeeded;
  final String? transcript;
  final LatLng location;
  final DateTime createdAt;
  final DriverIncidentHospital? assignedHospital;

  const DriverIncidentDetail({
    required this.id,
    required this.status,
    this.severity,
    this.emergencyType,
    this.symptoms = const [],
    this.victims = 1,
    this.departmentNeeded,
    this.transcript,
    required this.location,
    required this.createdAt,
    this.assignedHospital,
  });

  factory DriverIncidentDetail.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>;
    final hosp = j['assigned_hospital'] as Map<String, dynamic>?;

    return DriverIncidentDetail(
      id: j['id'] as int,
      status: j['status'] as String,
      severity: j['severity'] as String?,
      emergencyType: j['emergency_type'] as String?,
      symptoms: List<String>.from(j['symptoms'] as List? ?? []),
      victims: (j['victims'] as int?) ?? 1,
      departmentNeeded: j['department_needed'] as String?,
      transcript: j['transcript'] as String?,
      location: LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      ),
      createdAt: DateTime.parse(j['created_at'] as String),
      assignedHospital:
          hosp != null ? DriverIncidentHospital.fromJson(hosp) : null,
    );
  }
}
