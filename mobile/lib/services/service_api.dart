import '../core/constants/api_endpoints.dart';
import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../models/service.dart';

class ServiceApi {
  const ServiceApi(this._client);

  final ApiClient _client;

  Future<Paged<Service>> list({
    int page = 1,
    int limit = 20,
    String? search,
    String? status,
    String? category,
  }) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.services,
      query: <String, dynamic>{
        'page': page,
        'limit': limit,
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null) 'status': status,
        if (category != null) 'category': category,
      },
      parse: Parse.list,
    );

    return Paged<Service>(
      items: response.data.map(Service.fromJson).toList(growable: false),
      meta: response.meta ?? PageMeta(page: page, limit: limit, total: response.data.length, totalPages: 1),
    );
  }

  Future<Service> byId(int id) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.service(id),
      parse: Parse.object,
    );
    return Service.fromJson(response.data);
  }

  /// This endpoint returns a list of plain strings, not objects, so it needs
  /// its own parser rather than [Parse.list].
  Future<List<String>> categories() async {
    final ApiResponse<List<String>> response = await _client.get<List<String>>(
      ApiEndpoints.serviceCategories,
      parse: (dynamic data) =>
          data is List ? data.whereType<String>().toList(growable: false) : const <String>[],
    );
    return response.data;
  }

  Future<List<ServiceHours>> hours(int serviceId) async {
    final response = await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.serviceHours(serviceId),
      parse: Parse.list,
    );
    return response.data.map(ServiceHours.fromJson).toList(growable: false);
  }
}
