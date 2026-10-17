// lib/driver_app/models/driver.dart
//
// Data classes for the driver authentication flow.
// These are plain Dart objects — no ORM, no generated code.

class DriverModel {
  final int id;
  final String name;
  final String email;
  final String? photoUrl;

  const DriverModel({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
  });

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    return DriverModel(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      photoUrl: json['photo_url'] as String?,
    );
  }
}

class AmbulanceModel {
  final int id;
  final String registrationNumber;
  final String? vehicleType;
  final bool isAvailable;

  const AmbulanceModel({
    required this.id,
    required this.registrationNumber,
    this.vehicleType,
    required this.isAvailable,
  });

  factory AmbulanceModel.fromJson(Map<String, dynamic> json) {
    return AmbulanceModel(
      id: json['id'] as int,
      registrationNumber: json['registration_number'] as String,
      vehicleType: json['vehicle_type'] as String?,
      isAvailable: json['is_available'] as bool,
    );
  }
}
