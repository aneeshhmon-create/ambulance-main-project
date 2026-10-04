/// Data model representing a registered User in the system.
class User {
  final int id;
  final String name;
  final String phone;

  const User({
    required this.id,
    required this.name,
    required this.phone,
  });

  /// Creates a [User] from a JSON map returned by the backend or local storage.
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      phone: json['phone'] as String,
    );
  }

  /// Converts this [User] to a JSON map for storage.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          phone == other.phone;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ phone.hashCode;

  @override
  String toString() => 'User(id: $id, name: $name, phone: $phone)';
}
