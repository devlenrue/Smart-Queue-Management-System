import 'package:flutter/foundation.dart';

import '../models/admin_queue_status.dart';
import '../models/api_exception.dart';
import '../models/service.dart';
import '../services/api_service.dart';

class AdminProvider extends ChangeNotifier {
  AdminProvider(this._api);

  final ApiClient _api;

  List<ServiceModel> _services = <ServiceModel>[];
  AdminQueueStatus? _queue;
  int? _selectedServiceId;
  bool _isLoading = false;
  bool _isActionLoading = false;
  String? _error;

  List<ServiceModel> get services => List.unmodifiable(_services);
  AdminQueueStatus? get queue => _queue;
  int? get selectedServiceId => _selectedServiceId;
  bool get isLoading => _isLoading;
  bool get isActionLoading => _isActionLoading;
  String? get error => _error;

  Future<void> loadServices() async {
    _setLoading(true);
    _error = null;
    try {
      _services = await _api.getServices();
      if (_services.isNotEmpty &&
          !_services.any((service) => service.id == _selectedServiceId)) {
        _selectedServiceId = _services.first.id;
      }
      if (_selectedServiceId != null) {
        await loadQueue(_selectedServiceId!);
      }
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Unable to load admin services.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadQueue(int serviceId) async {
    _selectedServiceId = serviceId;
    try {
      _queue = await _api.getAdminQueue(serviceId);
      _error = null;
      notifyListeners();
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
    } catch (_) {
      _error = 'Unable to load the live queue.';
      notifyListeners();
    }
  }

  Future<bool> callNext() async {
    final serviceId = _selectedServiceId;
    if (serviceId == null) return false;
    return _runAction(() async {
      await _api.callNext(serviceId);
      await loadQueue(serviceId);
    });
  }

  Future<bool> complete(int ticketId) async {
    return _runAction(() async {
      await _api.completeTicket(ticketId);
      if (_selectedServiceId != null) await loadQueue(_selectedServiceId!);
    });
  }

  Future<bool> skip(int ticketId) async {
    return _runAction(() async {
      await _api.skipTicket(ticketId);
      if (_selectedServiceId != null) await loadQueue(_selectedServiceId!);
    });
  }

  Future<bool> addService({
    required String name,
    required String description,
    required double averageServiceMinutes,
  }) async {
    return _runAction(() async {
      final service = await _api.addService(
        name: name,
        description: description.isEmpty ? null : description,
        averageServiceMinutes: averageServiceMinutes,
      );
      _services = <ServiceModel>[..._services, service]
        ..sort((a, b) => a.name.compareTo(b.name));
      _selectedServiceId = service.id;
      await loadQueue(service.id);
    });
  }

  Future<bool> removeSelectedService() async {
    final serviceId = _selectedServiceId;
    if (serviceId == null) return false;
    return _runAction(() async {
      await _api.removeService(serviceId);
      _services = _services.where((service) => service.id != serviceId).toList();
      _queue = null;
      _selectedServiceId = _services.isEmpty ? null : _services.first.id;
      if (_selectedServiceId != null) await loadQueue(_selectedServiceId!);
    });
  }

  Future<bool> _runAction(Future<void> Function() action) async {
    _setActionLoading(true);
    _error = null;
    try {
      await action();
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } catch (_) {
      _error = 'The queue action could not be completed.';
      return false;
    } finally {
      _setActionLoading(false);
    }
  }

  void clear() {
    _services = <ServiceModel>[];
    _queue = null;
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
