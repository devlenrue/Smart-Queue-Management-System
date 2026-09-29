import '../core/constants/enums.dart';
import '../core/utils/json.dart';

/// Where a clerk is posted: the service, and the counter inside it.
///
/// Null on a [StaffMember] who has been created but not yet placed — the
/// roster shows those as "Not posted" so an administrator can see at a glance
/// who is idle.
class RosterPosting {
  const RosterPosting({
    required this.assignmentId,
    required this.serviceId,
    this.serviceName,
    this.serviceCode,
    this.counterId,
    this.counterNumber,
    this.counterName,
    this.counterStatus,
    this.assignedAt,
  });

  final int assignmentId;
  final int serviceId;
  final String? serviceName;
  final String? serviceCode;
  final int? counterId;
  final int? counterNumber;
  final String? counterName;
  final CounterStatus? counterStatus;
  final String? assignedAt;

  factory RosterPosting.fromJson(Map<String, dynamic> json) {
    final String? status = Json.asStringOrNull(json['counterStatus']);
    return RosterPosting(
      assignmentId: Json.asInt(json['assignmentId']),
      serviceId: Json.asInt(json['serviceId']),
      serviceName: Json.asStringOrNull(json['serviceName']),
      serviceCode: Json.asStringOrNull(json['serviceCode']),
      counterId: Json.asIntOrNull(json['counterId']),
      counterNumber: Json.asIntOrNull(json['counterNumber']),
      counterName: Json.asStringOrNull(json['counterName']),
      counterStatus: status == null ? null : CounterStatus.parse(status),
      assignedAt: Json.asStringOrNull(json['assignedAt']),
    );
  }

  /// `Finance Office · Counter 2`, or just the service when the posting has
  /// no counter attached.
  String get label {
    final String service = serviceName ?? serviceCode ?? 'Service $serviceId';
    if (counterNumber == null) return service;
    return '$service · Counter $counterNumber';
  }
}

/// A row of the staff roster (§55): the person, plus where they are working.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    this.createdAt,
    this.posting,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String fullName;
  final String email;
  final String phone;
  final UserRole role;
  final UserStatus status;
  final String? createdAt;
  final RosterPosting? posting;

  bool get isPosted => posting != null;

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? posting = Json.asMap(json['posting']);
    return StaffMember(
      id: Json.asInt(json['id']),
      firstName: Json.asString(json['firstName']),
      lastName: Json.asString(json['lastName']),
      fullName: Json.asString(json['fullName']),
      email: Json.asString(json['email']),
      phone: Json.asString(json['phone']),
      role: UserRole.parse(Json.asStringOrNull(json['role'])),
      status: UserStatus.parse(Json.asStringOrNull(json['status'])),
      createdAt: Json.asStringOrNull(json['createdAt']),
      posting: posting == null ? null : RosterPosting.fromJson(posting),
    );
  }
}
