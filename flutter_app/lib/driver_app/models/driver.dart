// lib/driver_app/models/driver.dart
//
// Data classes for the driver authentication flow.
// These are plain Dart objects — no ORM, no generated code.

class DriverModel {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;

  const DriverModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.photoUrl,
  });

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    return DriverModel(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String?,
      photoUrl: json['photo_url'] as String?,
    );
  }
}

class AmbulanceModel {
  final int id;
  final String registrationNumber;
  final String? vehicleType;
  final bool isAvailable;
  final bool isOnline;

  const AmbulanceModel({
    required this.id,
    required this.registrationNumber,
    this.vehicleType,
    required this.isAvailable,
    this.isOnline = false,
  });

  factory AmbulanceModel.fromJson(Map<String, dynamic> json) {
    return AmbulanceModel(
      id: json['id'] as int,
      registrationNumber: json['registration_number'] as String,
      vehicleType: json['vehicle_type'] as String?,
      isAvailable: json['is_available'] as bool,
      isOnline: (json['is_online'] as bool?) ?? false,
    );
  }

  AmbulanceModel copyWith({bool? isOnline}) {
    return AmbulanceModel(
      id: id,
      registrationNumber: registrationNumber,
      vehicleType: vehicleType,
      isAvailable: isAvailable,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
