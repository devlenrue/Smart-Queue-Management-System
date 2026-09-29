import '../core/constants/enums.dart';
import '../core/utils/json.dart';
import 'counter.dart';

/// The live queue figures attached to every service card (§15).
/// These come from the server on every read — nothing here is computed
/// client-side, which is the whole point of the endpoint.
class QueueSummary {
  const QueueSummary({
    required this.queueId,
    required this.status,
    required this.waitingCount,
    required this.servingCount,
    required this.completedToday,
    required this.estimatedWaitMinutes,
    required this.activeCounters,
    required this.isAcceptingTickets,
    required this.capacityRemaining,
    this.nowServing,
  });

  final int queueId;
  final QueueStatus status;
  final int waitingCount;
  final int servingCount;
  final int completedToday;
  final int estimatedWaitMinutes;
  final int activeCounters;
  final bool isAcceptingTickets;
  final int capacityRemaining;
  final String? nowServing;

  factory QueueSummary.fromJson(Map<String, dynamic> json) {
    return QueueSummary(
      queueId: Json.asInt(json['queueId']),
      status: QueueStatus.parse(Json.asStringOrNull(json['status'])),
      waitingCount: Json.asInt(json['waitingCount']),
      servingCount: Json.asInt(json['servingCount']),
      completedToday: Json.asInt(json['completedToday']),
      estimatedWaitMinutes: Json.asInt(json['estimatedWaitMinutes']),
      activeCounters: Json.asInt(json['activeCounters']),
      isAcceptingTickets: Json.asBool(json['isAcceptingTickets']),
      capacityRemaining: Json.asInt(json['capacityRemaining']),
      nowServing: Json.asStringOrNull(json['nowServing']),
    );
  }
}

class ServiceHours {
  const ServiceHours({
    required this.dayOfWeek,
    required this.dayName,
    required this.isOpen,
    this.openingTime,
    this.closingTime,
  });

  final int dayOfWeek;
  final String dayName;
  final bool isOpen;
  final String? openingTime;
  final String? closingTime;

  factory ServiceHours.fromJson(Map<String, dynamic> json) {
    return ServiceHours(
      dayOfWeek: Json.asInt(json['dayOfWeek']),
      dayName: Json.asString(json['dayName']),
      isOpen: Json.asString(json['status']) == 'open',
      openingTime: Json.asStringOrNull(json['openingTime']),
      closingTime: Json.asStringOrNull(json['closingTime']),
    );
  }

  String get range =>
      isOpen && openingTime != null && closingTime != null ? '$openingTime – $closingTime' : 'Closed';
}

/// Today's window, plus whether the door is open right now.
class TodayHours {
  const TodayHours({this.opensAt, this.closesAt, this.isOpenNow = false});

  final String? opensAt;
  final String? closesAt;
  final bool isOpenNow;

  factory TodayHours.fromJson(Map<String, dynamic> json) {
    return TodayHours(
      opensAt: Json.asStringOrNull(json['opensAt']),
      closesAt: Json.asStringOrNull(json['closesAt']),
      isOpenNow: Json.asBool(json['isOpenNow']),
    );
  }

  String get label {
    if (opensAt == null || closesAt == null) return 'Hours not set';
    return '$opensAt – $closesAt';
  }
}

class QueueSettings {
  const QueueSettings({
    required this.maxQueueSize,
    required this.allowCancellation,
    required this.allowRejoin,
    required this.notificationThreshold,
    required this.estimatedServiceTime,
  });

  final int maxQueueSize;
  final bool allowCancellation;
  final bool allowRejoin;
  final int notificationThreshold;
  final int estimatedServiceTime;

  factory QueueSettings.fromJson(Map<String, dynamic> json) {
    return QueueSettings(
      maxQueueSize: Json.asInt(json['maxQueueSize'], 100),
      allowCancellation: Json.asBool(json['allowCancellation'], true),
      allowRejoin: Json.asBool(json['allowRejoin'], true),
      notificationThreshold: Json.asInt(json['notificationThreshold'], 3),
      estimatedServiceTime: Json.asInt(json['estimatedServiceTime'], 5),
    );
  }
}

/// One service in the catalogue. The optional members are only populated on
/// the detail endpoint, so a list response stays small.
class Service {
  const Service({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    required this.averageServiceTime,
    required this.dailyCapacity,
    this.description,
    this.category,
    this.queue,
    this.hoursToday,
    this.hours = const <ServiceHours>[],
    this.counters = const <ServiceCounter>[],
    this.settings,
  });

  final int id;
  final String name;
  final String code;
  final ServiceStatus status;
  final int averageServiceTime;
  final int dailyCapacity;
  final String? description;
  final String? category;
  final QueueSummary? queue;
  final TodayHours? hoursToday;
  final List<ServiceHours> hours;
  final List<ServiceCounter> counters;
  final QueueSettings? settings;

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: Json.asInt(json['id']),
      name: Json.asString(json['name']),
      code: Json.asString(json['code']),
      status: ServiceStatus.parse(Json.asStringOrNull(json['status'])),
      averageServiceTime: Json.asInt(json['averageServiceTime'], 5),
      dailyCapacity: Json.asInt(json['dailyCapacity'], 100),
      description: Json.asStringOrNull(json['description']),
      category: Json.asStringOrNull(json['category']),
      queue: Json.asMap(json['queue']) == null ? null : QueueSummary.fromJson(json['queue'] as Map<String, dynamic>),
      hoursToday: Json.asMap(json['hoursToday']) == null
          ? null
          : TodayHours.fromJson(json['hoursToday'] as Map<String, dynamic>),
      hours: Json.mapList(json['hours'], ServiceHours.fromJson),
      counters: Json.mapList(json['counters'], ServiceCounter.fromJson),
      settings: Json.asMap(json['settings']) == null
          ? null
          : QueueSettings.fromJson(json['settings'] as Map<String, dynamic>),
    );
  }

  /// The single question the Join button asks. Deliberately conservative:
  /// the server decides for real, this only keeps the button honest.
  bool get canJoin =>
      status == ServiceStatus.open && (queue?.isAcceptingTickets ?? false);

  /// Why the Join button is disabled, phrased for a human.
  String get unavailableReason {
    if (status == ServiceStatus.inactive) return 'Not available';
    if (status == ServiceStatus.closed) return 'Closed';
    final QueueSummary? summary = queue;
    if (summary == null) return 'Unavailable';
    if (summary.status == QueueStatus.paused) return 'Queue paused';
    if (summary.status == QueueStatus.closed) return 'Queue closed for today';
    if (summary.capacityRemaining <= 0) return 'Queue full';
    if (hoursToday != null && !hoursToday!.isOpenNow) return 'Outside opening hours';
    return 'Unavailable';
  }

  int get waitingCount => queue?.waitingCount ?? 0;
  int get estimatedWaitMinutes => queue?.estimatedWaitMinutes ?? 0;
  String? get nowServing => queue?.nowServing;
}
