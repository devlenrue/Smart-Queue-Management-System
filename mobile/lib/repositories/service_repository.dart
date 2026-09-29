import '../core/network/api_response.dart';
import '../models/service.dart';
import '../services/service_api.dart';

class ServiceRepository {
  ServiceRepository(this._api);

  final ServiceApi _api;

  /// Categories change about once a semester, so they are cached for the
  /// life of the app rather than re-fetched every time a filter opens.
  List<String>? _categoryCache;

  Future<Paged<Service>> list({
    int page = 1,
    int limit = 20,
    String? search,
    String? category,
  }) {
    return _api.list(page: page, limit: limit, search: search, category: category);
  }

  Future<Service> byId(int id) => _api.byId(id);

  Future<List<ServiceHours>> hours(int serviceId) => _api.hours(serviceId);

  Future<List<String>> categories({bool refresh = false}) async {
    if (!refresh && _categoryCache != null) return _categoryCache!;
    final List<String> result = await _api.categories();
    _categoryCache = result;
    return result;
  }
}
