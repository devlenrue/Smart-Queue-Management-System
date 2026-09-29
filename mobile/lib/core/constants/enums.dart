/// Client-side mirrors of the server enums.
///
/// Each one parses defensively: an unrecognised string from a newer server
/// falls back to a sane value rather than throwing inside a list builder.
library;

enum UserRole {
  customer,
  staff,
  admin,
  superAdmin;

  static UserRole parse(String? value) {
    switch (value) {
      case 'staff':
        return UserRole.staff;
      case 'admin':
        return UserRole.admin;
      case 'super_admin':
        return UserRole.superAdmin;
      default:
        return UserRole.customer;
    }
  }

  String get wire => this == UserRole.superAdmin ? 'super_admin' : name;

  bool get isCustomer => this == UserRole.customer;
  bool get isStaff => this == UserRole.staff;
  bool get isAdmin => this == UserRole.admin || this == UserRole.superAdmin;

  String get label {
    switch (this) {
      case UserRole.customer:
        return 'Customer';
      case UserRole.staff:
        return 'Staff';
      case UserRole.admin:
        return 'Administrator';
      case UserRole.superAdmin:
        return 'Super administrator';
    }
  }
}

enum UserStatus {
  active,
  inactive,
  suspended;

  static UserStatus parse(String? value) {
    switch (value) {
      case 'inactive':
        return UserStatus.inactive;
      case 'suspended':
        return UserStatus.suspended;
      default:
        return UserStatus.active;
    }
  }
}

enum ServiceStatus {
  open,
  closed,
  inactive;

  static ServiceStatus parse(String? value) {
    switch (value) {
      case 'closed':
        return ServiceStatus.closed;
      case 'inactive':
        return ServiceStatus.inactive;
      default:
        return ServiceStatus.open;
    }
  }

  String get label {
    switch (this) {
      case ServiceStatus.open:
        return 'Open';
      case ServiceStatus.closed:
        return 'Closed';
      case ServiceStatus.inactive:
        return 'Unavailable';
    }
  }
}

enum QueueStatus {
  waiting,
  paused,
  closed;

  static QueueStatus parse(String? value) {
    switch (value) {
      case 'paused':
        return QueueStatus.paused;
      case 'closed':
        return QueueStatus.closed;
      default:
        return QueueStatus.waiting;
    }
  }

  String get label {
    switch (this) {
      case QueueStatus.waiting:
        return 'Open';
      case QueueStatus.paused:
        return 'Paused';
      case QueueStatus.closed:
        return 'Closed';
    }
  }
}

enum CounterStatus {
  available,
  busy,
  offline;

  static CounterStatus parse(String? value) {
    switch (value) {
      case 'busy':
        return CounterStatus.busy;
      case 'offline':
        return CounterStatus.offline;
      default:
        return CounterStatus.available;
    }
  }

  /// All three spell the same on the wire; the getter exists so call sites
  /// read the same as they do for [TicketStatus], which does not.
  String get wire => name;

  String get label {
    switch (this) {
      case CounterStatus.available:
        return 'Available';
      case CounterStatus.busy:
        return 'Busy';
      case CounterStatus.offline:
        return 'Offline';
    }
  }
}

/// The seven ticket states of `docs/queue-engine.md` §1.
enum TicketStatus {
  waiting,
  called,
  serving,
  completed,
  cancelled,
  skipped,
  noShow;

  static TicketStatus parse(String? value) {
    switch (value) {
      case 'called':
        return TicketStatus.called;
      case 'serving':
        return TicketStatus.serving;
      case 'completed':
        return TicketStatus.completed;
      case 'cancelled':
        return TicketStatus.cancelled;
      case 'skipped':
        return TicketStatus.skipped;
      case 'no_show':
        return TicketStatus.noShow;
      default:
        return TicketStatus.waiting;
    }
  }

  String get wire => this == TicketStatus.noShow ? 'no_show' : name;

  String get label {
    switch (this) {
      case TicketStatus.waiting:
        return 'Waiting';
      case TicketStatus.called:
        return 'Called';
      case TicketStatus.serving:
        return 'Being served';
      case TicketStatus.completed:
        return 'Completed';
      case TicketStatus.cancelled:
        return 'Cancelled';
      case TicketStatus.skipped:
        return 'Skipped';
      case TicketStatus.noShow:
        return 'No show';
    }
  }

  /// Live tickets are the ones that still hold a place in the queue.
  bool get isActive =>
      this == TicketStatus.waiting || this == TicketStatus.called || this == TicketStatus.serving;

  bool get isFinished => !isActive;

  /// Only a waiting ticket can be given up by the customer (§27).
  bool get canCancel => this == TicketStatus.waiting;
}

enum NotificationType {
  queue,
  system,
  announcement,
  service;

  static NotificationType parse(String? value) {
    switch (value) {
      case 'system':
        return NotificationType.system;
      case 'announcement':
        return NotificationType.announcement;
      case 'service':
        return NotificationType.service;
      default:
        return NotificationType.queue;
    }
  }
}
