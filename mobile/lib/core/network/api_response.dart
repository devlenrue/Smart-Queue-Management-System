/// The success envelope of `docs/api.md` §1, parsed once.
///
/// ```json
/// { "success": true, "message": "...", "data": …, "meta": { … } }
/// ```
class ApiResponse<T> {
  const ApiResponse({
    required this.message,
    required this.data,
    this.meta,
  });

  final String message;
  final T data;
  final PageMeta? meta;

  /// [parse] receives the raw `data` member and produces the typed value.
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic data) parse,
  ) {
    return ApiResponse<T>(
      message: json['message'] is String ? json['message'] as String : '',
      data: parse(json['data']),
      meta: json['meta'] is Map<String, dynamic>
          ? PageMeta.fromJson(json['meta'] as Map<String, dynamic>)
          : null,
    );
  }
}

class PageMeta {
  const PageMeta({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  final int page;
  final int limit;
  final int total;
  final int totalPages;

  factory PageMeta.fromJson(Map<String, dynamic> json) {
    return PageMeta(
      page: _int(json['page'], 1),
      limit: _int(json['limit'], 20),
      total: _int(json['total'], 0),
      totalPages: _int(json['totalPages'], 0),
    );
  }

  bool get hasMore => page < totalPages;

  static int _int(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}

/// A page of results plus the metadata needed to ask for the next one.
class Paged<T> {
  const Paged({required this.items, required this.meta});

  final List<T> items;
  final PageMeta meta;

  bool get hasMore => meta.hasMore;

  static Paged<T> empty<T>() => Paged<T>(
        items: const <Never>[],
        meta: const PageMeta(page: 1, limit: 20, total: 0, totalPages: 0),
      );
}
