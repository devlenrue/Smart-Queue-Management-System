import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_exception.dart';
import '../models/queue_status.dart';
import '../models/service.dart';
import '../models/ticket.dart';
import '../services/api_service.dart';

class QueueProvider extends ChangeNotifier {
  QueueProvider(this._api);

  final ApiClient _api;
  Timer? _pollTimer;
  bool _refreshingStatus = false;

  List<ServiceModel> _services = <ServiceModel>[];
  List<Ticket> _history = <Ticket>[];
  QueueStatus? _status;
  int? _selectedServiceId;
  bool _isLoading = false;
  bool _isActionLoading = false;
  String? _error;

  List<ServiceModel> get services => List.unmodifiable(_services);
  List<Ticket> get history => List.unmodifiable(_history);
  QueueStatus? get status => _status;
  int? get selectedServiceId => _selectedServiceId;
  bool get isLoading => _isLoading;
  bool get isActionLoading => _isActionLoading;
  String? get error => _error;

  Ticket? get activeTicket {
    for (final ticket in _history) {
      if (ticket.isActive) return ticket;
    }
    return null;
  }

  Future<void> loadServices() async {
    _setLoading(true);
    _error = null;
    try {
      _services = await _api.getServices();
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Unable to load services.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadHistory() async {
    try {
      _history = await _api.getHistory();
      notifyListeners();
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
    } catch (_) {
      _error = 'Unable to load queue history.';
      notifyListeners();
    }
  }

  Future<Ticket?> joinQueue(ServiceModel service) async {
    _setActionLoading(true);
    _error = null;
    try {
      final ticket = await _api.joinQueue(service.id);
      _history = <Ticket>[ticket, ..._history];
      return ticket;
    } on ApiException catch (error) {
      _error = error.message;
      return null;
    } catch (_) {
      _error = 'Unable to join the queue.';
      return null;
    } finally {
      _setActionLoading(false);
    }
  }

  void startPolling(int serviceId) {
    _selectedServiceId = serviceId;
    _status = null;
    _pollTimer?.cancel();
    notifyListeners();
    unawaited(loadStatus(serviceId));
    _pollTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      unawaited(loadStatus(serviceId));
    });
  }

  Future<void> loadStatus(int serviceId) async {
    if (_refreshingStatus) return;
    _refreshingStatus = true;
    try {
      _status = await _api.getQueueStatus(serviceId);
      _error = null;
      notifyListeners();
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
    } catch (_) {
      _error = 'Unable to refresh queue status.';
      notifyListeners();
    } finally {
      _refreshingStatus = false;
    }
  }

  Future<bool> cancelTicket(int ticketId) async {
    _setActionLoading(true);
    _error = null;
    try {
      final cancelled = await _api.cancelTicket(ticketId);
      _history = _history
          .map((ticket) => ticket.id == cancelled.id ? cancelled : ticket)
          .toList();
      if (_selectedServiceId != null) {
        await loadStatus(_selectedServiceId!);
      }
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } catch (_) {
      _error = 'Unable to cancel this ticket.';
      return false;
    } finally {
      _setActionLoading(false);
    }
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void clear() {
    stopPolling();
    _services = <ServiceModel>[];
    _history = <Ticket>[];
    _status = null;
    _selectedServiceId = null;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setActionLoading(bool value) {
    _isActionLoading = value;
    notifyListeners();
  }
}
