import '../core/network/api_response.dart';

/// List-screen state: the rows so far, where we are in the pagination, and
/// whether another page is on the way.
///
/// `isLoadingMore` is kept separate from Riverpod's `AsyncLoading` because a
/// "load more" must not blank out the rows already on screen.
class PagedState<T> {
  const PagedState({
    required this.items,
    required this.meta,
    this.isLoadingMore = false,
  });

  final List<T> items;
  final PageMeta meta;
  final bool isLoadingMore;

  bool get isEmpty => items.isEmpty;
  bool get hasMore => meta.hasMore;

  factory PagedState.fromPage(Paged<T> page) => PagedState<T>(items: page.items, meta: page.meta);

  PagedState<T> appending(Paged<T> next) {
    return PagedState<T>(items: <T>[...items, ...next.items], meta: next.meta);
  }

  PagedState<T> loadingMore() => PagedState<T>(items: items, meta: meta, isLoadingMore: true);

  PagedState<T> withItems(List<T> next) =>
      PagedState<T>(items: next, meta: meta, isLoadingMore: isLoadingMore);
}
