// lib/services/incident_service.dart
//
// Thin HTTP client for the ambulance-allocation backend.
// Base URL is set here -- replace <my-local-ip> with your machine IP.

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Change this to your laptop IP when testing on a physical device/emulator.
const String kBaseUrl = 'http://localhost:8000';

class IncidentData {
  final int id;
  final String status;
  final int? assignedHospitalId;
  final int? assignedAmbulanceId;
  final String? transcript;
  final String? emergencyType;
  final String? severity;
  final String? departmentNeeded;
  final List<Map<String, dynamic>> broadcasts;

  const IncidentData({
    required this.id,
    required this.status,
    this.assignedHospitalId,
    this.assignedAmbulanceId,
    this.transcript,
    this.emergencyType,
    this.severity,
    this.departmentNeeded,
    required this.broadcasts,
  });

  factory IncidentData.fromJson(Map<String, dynamic> json) {
    return IncidentData(
      id: json['id'] as int,
      status: json['status'] as String? ?? 'pending',
      assignedHospitalId: json['assigned_hospital_id'] as int?,
      assignedAmbulanceId: json['assigned_ambulance_id'] as int?,
      transcript: json['transcript'] as String?,
      emergencyType: json['emergency_type'] as String?,
      severity: json['severity'] as String?,
      departmentNeeded: json['department_needed'] as String?,
      broadcasts: (json['broadcasts'] as List<dynamic>?)
              ?.map((b) => b as Map<String, dynamic>)
              .toList() ??
          [],
    );
  }
}

class IncidentServiceException implements Exception {
  final String message;
  const IncidentServiceException(this.message);
  @override
  String toString() => message;
}

class IncidentService {
  static Future<IncidentData> fetchIncident(int incidentId) async {
    final uri = Uri.parse('$kBaseUrl/incidents/$incidentId');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return IncidentData.fromJson(json);
      } else if (response.statusCode == 404) {
        throw const IncidentServiceException('Incident not found.');
      } else {
        throw IncidentServiceException(
            'Server error (${ response.statusCode }). Please try again.');
      }
    } on IncidentServiceException {
      rethrow;
    } catch (e) {
      throw const IncidentServiceException(
          'Network error: Could not reach the server. Check your connection.');
    }
  }
}