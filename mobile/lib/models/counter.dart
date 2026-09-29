import '../core/constants/enums.dart';
import '../core/utils/json.dart';

/// The compact counter reference embedded in a ticket.
class CounterSummary {
  const CounterSummary({required this.id, required this.counterNumber, required this.name});

  final int id;
  final int counterNumber;
  final String name;

  factory CounterSummary.fromJson(Map<String, dynamic> json) {
    return CounterSummary(
      id: Json.asInt(json['id']),
      counterNumber: Json.asInt(json['counterNumber']),
      name: Json.asString(json['name']),
    );
  }

  String get shortLabel => 'Counter $counterNumber';
}

/// The full counter row, as the service detail and admin screens show it.
class ServiceCounter {
  const ServiceCounter({
    required this.id,
    required this.serviceId,
    required this.counterNumber,
    required this.name,
    required this.status,
    this.staffName,
    this.staffId,
    this.currentTicket,
  });

  final int id;
  final int serviceId;
  final int counterNumber;
  final String name;
  final CounterStatus status;
  final String? staffName;
  final int? staffId;
  final String? currentTicket;

  bool get isStaffed => staffId != null;

  factory ServiceCounter.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? staff = Json.asMap(json['staff']);
    return ServiceCounter(
      id: Json.asInt(json['id']),
      serviceId: Json.asInt(json['serviceId']),
      counterNumber: Json.asInt(json['counterNumber']),
      name: Json.asString(json['name']),
      status: CounterStatus.parse(Json.asStringOrNull(json['status'])),
      staffId: staff == null ? null : Json.asIntOrNull(staff['id']),
      staffName: staff == null ? null : Json.asStringOrNull(staff['fullName']),
      currentTicket: Json.asStringOrNull(json['currentTicket']),
    );
  }
}
