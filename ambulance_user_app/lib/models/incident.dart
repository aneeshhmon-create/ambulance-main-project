// ---------------------------------------------------------------------------
// Incident Models matching FastAPI schemas (IncidentOut, BroadcastOut, AmbulanceOut)
// ---------------------------------------------------------------------------

class IncidentLocation {
  const IncidentLocation({required this.lat, required this.lng});

  final double lat;
  final double lng;

  factory IncidentLocation.fromJson(Map<String, dynamic> json) {
    return IncidentLocation(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

class Broadcast {
  const Broadcast({
    required this.id,
    required this.incidentId,
    required this.targetType,
    required this.targetId,
    required this.status,
    this.sentAt,
    this.respondedAt,
  });

  final int id;
  final int incidentId;
  final String targetType;
  final int targetId;
  final String status;
  final DateTime? sentAt;
  final DateTime? respondedAt;

  factory Broadcast.fromJson(Map<String, dynamic> json) {
    return Broadcast(
      id: json['id'] as int? ?? 0,
      incidentId: json['incident_id'] as int? ?? 0,
      targetType: json['target_type'] as String? ?? 'hospital',
      targetId: json['target_id'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      sentAt: json['sent_at'] != null ? DateTime.tryParse(json['sent_at'].toString()) : null,
      respondedAt: json['responded_at'] != null
          ? DateTime.tryParse(json['responded_at'].toString())
          : null,
    );
  }
}

class AssignedAmbulance {
  const AssignedAmbulance({
    required this.id,
    required this.driverName,
    required this.driverPhone,
    this.location,
    this.isAvailable = false,
  });

  final int id;
  final String driverName;
  final String driverPhone;
  final IncidentLocation? location;
  final bool isAvailable;

  factory AssignedAmbulance.fromJson(Map<String, dynamic> json) {
    return AssignedAmbulance(
      id: json['id'] as int? ?? 0,
      driverName: json['driver_name'] as String? ?? '',
      driverPhone: json['driver_phone'] as String? ?? '',
      location: json['location'] is Map<String, dynamic>
          ? IncidentLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
      isAvailable: json['is_available'] as bool? ?? false,
    );
  }
}

class Incident {
  const Incident({
    required this.id,
    this.userId,
    required this.location,
    this.emergencyType,
    this.severity,
    this.symptoms = const [],
    this.victims = 1,
    this.departmentNeeded,
    this.status = 'pending',
    this.assignedHospitalId,
    this.assignedAmbulanceId,
    this.createdAt,
    this.broadcasts = const [],
    this.assignedAmbulance,
    this.transcript,
    this.extractedData,
  });

  final int id;
  final int? userId;
  final IncidentLocation location;
  final String? emergencyType;
  final String? severity;
  final List<String> symptoms;
  final int victims;
  final String? departmentNeeded;
  final String status;
  final int? assignedHospitalId;
  final int? assignedAmbulanceId;
  final DateTime? createdAt;

  final List<Broadcast> broadcasts;
  final AssignedAmbulance? assignedAmbulance;
  final String? transcript;
  final Map<String, dynamic>? extractedData;

  Incident copyWith({
    int? id,
    int? userId,
    IncidentLocation? location,
    String? emergencyType,
    String? severity,
    List<String>? symptoms,
    int? victims,
    String? departmentNeeded,
    String? status,
    int? assignedHospitalId,
    int? assignedAmbulanceId,
    DateTime? createdAt,
    List<Broadcast>? broadcasts,
    AssignedAmbulance? assignedAmbulance,
    String? transcript,
    Map<String, dynamic>? extractedData,
  }) {
    return Incident(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      location: location ?? this.location,
      emergencyType: emergencyType ?? this.emergencyType,
      severity: severity ?? this.severity,
      symptoms: symptoms ?? this.symptoms,
      victims: victims ?? this.victims,
      departmentNeeded: departmentNeeded ?? this.departmentNeeded,
      status: status ?? this.status,
      assignedHospitalId: assignedHospitalId ?? this.assignedHospitalId,
      assignedAmbulanceId: assignedAmbulanceId ?? this.assignedAmbulanceId,
      createdAt: createdAt ?? this.createdAt,
      broadcasts: broadcasts ?? this.broadcasts,
      assignedAmbulance: assignedAmbulance ?? this.assignedAmbulance,
      transcript: transcript ?? this.transcript,
      extractedData: extractedData ?? this.extractedData,
    );
  }

  /// Defensive JSON deserialization. Fallback extraction and missing fields
  /// never cause a parse crash.
  factory Incident.fromJson(Map<String, dynamic> json) {
    final rawLoc = json['location'];
    final loc = rawLoc is Map<String, dynamic>
        ? IncidentLocation.fromJson(rawLoc)
        : const IncidentLocation(lat: 0.0, lng: 0.0);

    final rawSymptoms = json['symptoms'];
    final symptomsList = rawSymptoms is List
        ? rawSymptoms.map((e) => e.toString()).toList()
        : <String>[];

    final rawBroadcasts = json['broadcasts'];
    final broadcastsList = rawBroadcasts is List
        ? rawBroadcasts
            .whereType<Map<String, dynamic>>()
            .map((b) => Broadcast.fromJson(b))
            .toList()
        : <Broadcast>[];

    final rawAmb = json['assigned_ambulance'];
    final amb = rawAmb is Map<String, dynamic>
        ? AssignedAmbulance.fromJson(rawAmb)
        : null;

    final rawExtracted = json['extracted_data'];
    final extractedMap = rawExtracted is Map<String, dynamic>
        ? rawExtracted
        : null;

    return Incident(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int?,
      location: loc,
      emergencyType: json['emergency_type'] as String?,
      severity: json['severity'] as String?,
      symptoms: symptomsList,
      victims: json['victims'] as int? ?? 1,
      departmentNeeded: json['department_needed'] as String?,
      status: json['status'] as String? ?? 'pending',
      assignedHospitalId: json['assigned_hospital_id'] as int?,
      assignedAmbulanceId: json['assigned_ambulance_id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      broadcasts: broadcastsList,
      assignedAmbulance: amb,
      transcript: json['transcript'] as String?,
      extractedData: extractedMap,
    );
  }
}
