import 'model_helpers.dart';

class User {
  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
  });

  final int id;
  final String fullName;
  final String email;
  final String role;

  bool get isCustomer => role == 'customer';
  bool get isStaff => role == 'staff' || role == 'admin';
  bool get isAdmin => role == 'admin';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: asInt(json['id']),
      fullName: json['fullName'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
    );
  }
}
