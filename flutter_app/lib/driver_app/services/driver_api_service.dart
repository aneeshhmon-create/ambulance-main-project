// lib/driver_app/services/driver_api_service.dart
//
// HTTP client for all driver home-screen backend calls:
//   • PATCH  /ambulances/{id}/online         – toggle online/offline
//   • GET    /ambulances/{id}/incidents       – list pending incident requests
//   • POST   /ambulances/{id}/incidents/{id}/accept – accept an incident
//   • GET    /ambulances/{id}/assignment      – poll active assignment
//
// All methods throw a [String] error message on failure.

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:ambulance_app/driver_app/config/api_config.dart';
import 'package:ambulance_app/driver_app/models/incident_detail.dart';

// ── DTOs ────────────────────────────────────────────────────────────────────

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

/// One pending incident requested to this ambulance.
class IncidentRequest {
  final int id;
  final String? severity;
  final String? emergencyType;
  final List<String> symptoms;
  final int victims;
  final String? departmentNeeded;
  final String? transcript;
  final LatLng location;
  final double? distanceKm;
  final DateTime createdAt;

  const IncidentRequest({
    required this.id,
    this.severity,
    this.emergencyType,
    required this.symptoms,
    required this.victims,
    this.departmentNeeded,
    this.transcript,
    required this.location,
    this.distanceKm,
    required this.createdAt,
  });

  factory IncidentRequest.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>;
    return IncidentRequest(
      id: j['id'] as int,
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
      distanceKm: j['distance_km'] != null
          ? (j['distance_km'] as num).toDouble()
          : null,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }
}

/// Active assignment returned by GET /ambulances/{id}/assignment.
class ActiveAssignment {
  final bool assigned;
  final int? incidentId;
  final String? incidentStatus;
  final String? emergencyType;
  final String? severity;
  final List<String> symptoms;
  final int? victims;
  final String? departmentNeeded;
  final LatLng? patientLocation;
  final String? patientName;
  final String? patientPhone;
  final String? hospitalName;
  final LatLng? hospitalLocation;
  final double? distanceToPatientKm;
  final double? distancePatientToHospitalKm;

  const ActiveAssignment({
    required this.assigned,
    this.incidentId,
    this.incidentStatus,
    this.emergencyType,
    this.severity,
    this.symptoms = const [],
    this.victims,
    this.departmentNeeded,
    this.patientLocation,
    this.patientName,
    this.patientPhone,
    this.hospitalName,
    this.hospitalLocation,
    this.distanceToPatientKm,
    this.distancePatientToHospitalKm,
  });

  factory ActiveAssignment.fromJson(Map<String, dynamic> j) {
    LatLng? _loc(dynamic map) {
      if (map == null) return null;
      final m = map as Map<String, dynamic>;
      return LatLng(
        (m['lat'] as num).toDouble(),
        (m['lng'] as num).toDouble(),
      );
    }

    final patient = j['patient'] as Map<String, dynamic>?;
    final hospital = j['hospital'] as Map<String, dynamic>?;

    return ActiveAssignment(
      assigned: j['assigned'] as bool,
      incidentId: j['incident_id'] as int?,
      incidentStatus: j['incident_status'] as String?,
      emergencyType: j['emergency_type'] as String?,
      severity: j['severity'] as String?,
      symptoms: List<String>.from(j['symptoms'] as List? ?? []),
      victims: j['victims'] as int?,
      departmentNeeded: j['department_needed'] as String?,
      patientLocation: _loc(j['patient_location']),
      patientName: patient?['name'] as String?,
      patientPhone: patient?['phone'] as String?,
      hospitalName: hospital?['name'] as String?,
      hospitalLocation: _loc(hospital?['location']),
      distanceToPatientKm: j['distance_to_patient_km'] != null
          ? (j['distance_to_patient_km'] as num).toDouble()
          : null,
      distancePatientToHospitalKm: j['distance_patient_to_hospital_km'] != null
          ? (j['distance_patient_to_hospital_km'] as num).toDouble()
          : null,
    );
  }
}

// ── Service ──────────────────────────────────────────────────────────────────

class DriverApiService {
  DriverApiService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  static Future<Map<String, String>> _authHeaders() async {
    final jwt = await _storage.read(key: 'driver_jwt');
    if (jwt == null) throw 'Not authenticated. Please sign in again.';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    };
  }

  static String _base(String path) =>
      '${DriverApiConfig.baseUrl}/ambulances$path';

  static String? _detail(http.Response r) {
    try {
      return (jsonDecode(r.body) as Map<String, dynamic>)['detail'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// PATCH /ambulances/{id}/online
  /// Toggles the ambulance online/offline state.
  /// When [isOnline] is true, pass the current GPS position if available.
  static Future<void> setOnline({
    required int ambulanceId,
    required bool isOnline,
    double? lat,
    double? lng,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{'is_online': isOnline};
    if (isOnline && lat != null && lng != null) {
      body['lat'] = lat;
      body['lng'] = lng;
    }
    final resp = await http
        .patch(
          Uri.parse(_base('/$ambulanceId/online')),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 409) {
      throw _detail(resp) ?? 'Cannot go offline: active incident in progress.';
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _detail(resp) ?? 'Server error ${resp.statusCode}';
    }
  }

  /// GET /ambulances/{id}/incidents
  /// Returns unassigned incidents requested to this ambulance.
  static Future<List<IncidentRequest>> fetchIncidents(int ambulanceId) async {
    final headers = await _authHeaders();
    final resp = await http
        .get(Uri.parse(_base('/$ambulanceId/incidents')), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 401) throw 'Session expired. Please sign in again.';
    if (resp.statusCode != 200) {
      throw _detail(resp) ?? 'Server error ${resp.statusCode}';
    }
    final list = jsonDecode(resp.body) as List<dynamic>;
    return list
        .map((e) => IncidentRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// PATCH /ambulances/{id}/location
  /// Pushes the driver's current GPS position to the backend.
  /// Called every 7 seconds while the ambulance is online.
  static Future<void> updateLocation({
    required int ambulanceId,
    required double lat,
    required double lng,
  }) async {
    final headers = await _authHeaders();
    final resp = await http
        .patch(
          Uri.parse(_base('/$ambulanceId/location')),
          headers: headers,
          body: jsonEncode({
            'location': {'lat': lat, 'lng': lng},
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // Non-fatal: silently log; caller catches and retries next tick
      throw _detail(resp) ?? 'Location update failed ${resp.statusCode}';
    }
  }

  /// POST /ambulances/{ambulanceId}/incidents/{incidentId}/accept
  /// Race-safe accept — throws on HTTP 409 (another ambulance won).
  static Future<void> acceptIncident({
    required int ambulanceId,
    required int incidentId,
  }) async {
    final headers = await _authHeaders();
    final resp = await http
        .post(
          Uri.parse(_base('/$ambulanceId/incidents/$incidentId/accept')),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 409) {
      throw _detail(resp) ?? 'Another ambulance already accepted this incident.';
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _detail(resp) ?? 'Server error ${resp.statusCode}';
    }
  }

  /// POST /ambulances/{ambulanceId}/incidents/{incidentId}/reject
  /// Turns down a requested incident; it will not be offered to this
  /// ambulance again. Throws on 409 (no longer requested to this ambulance).
  static Future<void> rejectIncident({
    required int ambulanceId,
    required int incidentId,
  }) async {
    final headers = await _authHeaders();
    final resp = await http
        .post(
          Uri.parse(_base('/$ambulanceId/incidents/$incidentId/reject')),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 409) {
      throw _detail(resp) ?? 'This incident is no longer available.';
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _detail(resp) ?? 'Server error ${resp.statusCode}';
    }
  }

  /// POST /ambulances/{ambulanceId}/incidents/{incidentId}/cancel
  /// Cancels an accepted incident: unassigns the ambulance, resets the
  /// incident to pending, and re-broadcasts it to other online ambulances.
  static Future<void> cancelIncident({
    required int ambulanceId,
    required int incidentId,
  }) async {
    final headers = await _authHeaders();
    final resp = await http
        .post(
          Uri.parse(_base('/$ambulanceId/incidents/$incidentId/cancel')),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 409) {
      throw _detail(resp) ?? 'Incident is already completed and cannot be cancelled.';
    }
    if (resp.statusCode == 403) {
      throw _detail(resp) ?? 'You are not the assigned driver for this incident.';
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _detail(resp) ?? 'Server error ${resp.statusCode}';
    }
  }

  /// GET /ambulances/{id}/assignment
  /// Polls the active assignment. Returns [assigned=false] when idle.
  static Future<ActiveAssignment> fetchAssignment(int ambulanceId) async {
    final headers = await _authHeaders();
    final resp = await http
        .get(Uri.parse(_base('/$ambulanceId/assignment')), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw _detail(resp) ?? 'Server error ${resp.statusCode}';
    }
    return ActiveAssignment.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// GET /ambulances/{ambulanceId}/incidents/{incidentId}
  /// Returns detailed incident information for driver navigation.
  static Future<DriverIncidentDetail> fetchIncidentDetail({
    required int ambulanceId,
    required int incidentId,
  }) async {
    final headers = await _authHeaders();
    final resp = await http
        .get(
          Uri.parse(_base('/$ambulanceId/incidents/$incidentId')),
          headers: headers,
        )
        .timeout(const Duration(seconds: 8));

    if (resp.statusCode == 401) {
      throw 'Session expired. Please sign in again.';
    }
    if (resp.statusCode == 403) {
      throw _detail(resp) ?? 'Access denied for this incident.';
    }
    if (resp.statusCode == 404) {
      throw _detail(resp) ?? 'Incident not found.';
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _detail(resp) ?? 'Server error ${resp.statusCode}';
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DriverIncidentDetail.fromJson(data);
  }
}
