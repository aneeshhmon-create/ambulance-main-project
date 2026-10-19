// lib/user_app/models/tracking.dart
//
// Data behind the live tracking map:
// GET /incidents/{incident_id}/tracking

import 'package:latlong2/latlong.dart';

LatLng _latLng(Map<String, dynamic> j) =>
    LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());

class TrackingHospital {
  final int id;
  final String name;
  final LatLng location;

  const TrackingHospital({
    required this.id,
    required this.name,
    required this.location,
  });

  factory TrackingHospital.fromJson(Map<String, dynamic> j) => TrackingHospital(
        id: j['id'] as int,
        name: j['name'] as String,
        location: _latLng(j['location'] as Map<String, dynamic>),
      );
}

class TrackingAmbulance {
  final int id;
  final String registrationNumber;
  final String? vehicleType;

  /// Last position reported by the ambulance; null until it has sent one.
  final LatLng? location;
  final DateTime? locationUpdatedAt;

  const TrackingAmbulance({
    required this.id,
    required this.registrationNumber,
    this.vehicleType,
    this.location,
    this.locationUpdatedAt,
  });

  factory TrackingAmbulance.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>?;
    final updated = j['location_updated_at'] as String?;
    return TrackingAmbulance(
      id: j['id'] as int,
      registrationNumber: j['registration_number'] as String,
      vehicleType: j['vehicle_type'] as String?,
      location: loc != null ? _latLng(loc) : null,
      locationUpdatedAt: updated != null ? DateTime.tryParse(updated) : null,
    );
  }
}

class IncidentTracking {
  final int id;
  final String status;
  final String? severity;
  final String? emergencyType;
  final List<String> symptoms;
  final int victims;
  final String? departmentNeeded;
  final String? transcript;
  final LatLng location;
  final TrackingHospital? assignedHospital;
  final TrackingAmbulance? ambulance;

  const IncidentTracking({
    required this.id,
    required this.status,
    this.severity,
    this.emergencyType,
    this.symptoms = const [],
    this.victims = 1,
    this.departmentNeeded,
    this.transcript,
    required this.location,
    this.assignedHospital,
    this.ambulance,
  });

  bool get isCompleted => status.toLowerCase() == 'completed';

  factory IncidentTracking.fromJson(Map<String, dynamic> j) {
    final hosp = j['assigned_hospital'] as Map<String, dynamic>?;
    final amb = j['ambulance'] as Map<String, dynamic>?;
    return IncidentTracking(
      id: j['id'] as int,
      status: j['status'] as String,
      severity: j['severity'] as String?,
      emergencyType: j['emergency_type'] as String?,
      symptoms: List<String>.from(j['symptoms'] as List? ?? const []),
      victims: (j['victims'] as int?) ?? 1,
      departmentNeeded: j['department_needed'] as String?,
      transcript: j['transcript'] as String?,
      location: _latLng(j['location'] as Map<String, dynamic>),
      assignedHospital: hosp != null ? TrackingHospital.fromJson(hosp) : null,
      ambulance: amb != null ? TrackingAmbulance.fromJson(amb) : null,
    );
  }
}
