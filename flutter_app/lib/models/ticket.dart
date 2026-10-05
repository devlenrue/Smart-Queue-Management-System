import 'model_helpers.dart';

class Ticket {
  const Ticket({
    required this.id,
    required this.serviceId,
    required this.userId,
    required this.ticketNumber,
    required this.ticketDate,
    required this.status,
    required this.joinedAt,
    this.calledAt,
    this.servedAt,
    this.cancelledAt,
    this.skippedAt,
    this.customerName,
    this.customerEmail,
    this.serviceName,
  });

  final int id;
  final int serviceId;
  final int userId;
  final int ticketNumber;
  final String ticketDate;
  final String status;
  final String joinedAt;
  final String? calledAt;
  final String? servedAt;
  final String? cancelledAt;
  final String? skippedAt;
  final String? customerName;
  final String? customerEmail;
  final String? serviceName;

  bool get isActive => status == 'waiting' || status == 'serving';

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: asInt(json['id']),
      serviceId: asInt(json['serviceId']),
      userId: asInt(json['userId']),
      ticketNumber: asInt(json['ticketNumber']),
      ticketDate: json['ticketDate']?.toString() ?? '',
      status: json['status'] as String,
      joinedAt: json['joinedAt']?.toString() ?? '',
      calledAt: asNullableString(json['calledAt']),
      servedAt: asNullableString(json['servedAt']),
      cancelledAt: asNullableString(json['cancelledAt']),
      skippedAt: asNullableString(json['skippedAt']),
      customerName: asNullableString(json['customerName']),
      customerEmail: asNullableString(json['customerEmail']),
      serviceName: asNullableString(json['serviceName']),
    );
  }
}
