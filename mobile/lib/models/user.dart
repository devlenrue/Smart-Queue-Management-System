import '../core/constants/enums.dart';
import '../core/utils/json.dart';

/// Mirrors the server's `UserDto`. There is no password field anywhere in
/// the client, by design.
class User {
  const User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    this.createdAt,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final UserRole role;
  final UserStatus status;
  final String? createdAt;

  String get fullName => '$firstName $lastName'.trim();

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: Json.asInt(json['id']),
      firstName: Json.asString(json['firstName']),
      lastName: Json.asString(json['lastName']),
      email: Json.asString(json['email']),
      phone: Json.asString(json['phone']),
      role: UserRole.parse(Json.asStringOrNull(json['role'])),
      status: UserStatus.parse(Json.asStringOrNull(json['status'])),
      createdAt: Json.asStringOrNull(json['createdAt']),
    );
  }

  User copyWith({String? firstName, String? lastName, String? email, String? phone}) {
    return User(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role,
      status: status,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) => other is User && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}

/// `POST /auth/login` and `/auth/register` both return this.
class AuthResult {
  const AuthResult({required this.token, required this.user, this.expiresAt});

  final String token;
  final User user;
  final String? expiresAt;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      token: Json.asString(json['token']),
      user: User.fromJson(Json.asMap(json['user']) ?? const <String, dynamic>{}),
      expiresAt: Json.asStringOrNull(json['expiresAt']),
    );
  }
}
