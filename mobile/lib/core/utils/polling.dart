/// Repeated polling, implemented once (§70).
///
/// There is no websocket in this project by design (§82), so "live" means
/// "re-read on a timer". The stream emits the first value immediately, then
/// every [interval].
///
/// Combined with Riverpod's `autoDispose`, the loop ends the moment the
/// screen leaves the tree: the subscription is cancelled, the generator is
/// resumed with a cancellation and the `while` exits. No timer leaks.
Stream<T> pollEvery<T>(
  Duration interval,
  Future<T> Function() fetch, {
  bool emitErrors = true,
}) async* {
  while (true) {
    try {
      yield await fetch();
    } catch (error) {
      // A single failed poll should not kill the stream — the network drops
      // in a queue hall constantly. Surface it once and keep trying.
      if (emitErrors) rethrow;
    }
    await Future<void>.delayed(interval);
  }
}

/// Polls, but keeps the last good value when a refresh fails.
///
/// This is what the ticket screen wants: if one poll times out, the customer
/// should keep seeing their position, not an error page.
Stream<T> pollKeepingLastValue<T>(
  Duration interval,
  Future<T> Function() fetch,
) async* {
  bool hasSucceeded = false;

  while (true) {
    try {
      final T value = await fetch();
      hasSucceeded = true;
      yield value;
    } catch (_) {
      // Only fail outright if we have never succeeded. After that, a failed
      // tick is ignored and the listener keeps the value it already has.
      if (!hasSucceeded) rethrow;
    }
    await Future<void>.delayed(interval);
  }
}
