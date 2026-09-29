/// Repeated polling, implemented once (§70).
///
/// There is no websocket in this project by design (§82), so "live" means
/// "re-read on a timer". A polled stream emits its first value immediately,
/// then one every interval, until the screen that wanted it goes away.
library;

import 'dart:async';

/// The cancellable pause between two polls.
///
/// A poll loop spends nearly all of its life asleep between reads, and
/// `Future.delayed` cannot be cancelled. Once the loop is inside one, that
/// timer stays on the event loop even after the provider has been disposed:
/// the app keeps a wake-up scheduled for a screen nobody is looking at, and
/// a widget test ends with *"A Timer is still pending even after the widget
/// tree was disposed"*.
///
/// Waiting for the timer to fire is not a reliable way out either. An
/// `async*` generator only learns that its listener has gone when it reaches
/// a `yield`; a loop whose read throws — and every one of these loops
/// deliberately swallows a failed poll so a dropped request does not blank a
/// live board — skips the yield, goes straight back to sleep and schedules
/// another timer. That loop never ends.
///
/// [PollClock] closes both holes. The pending timer is held in a field and
/// cancelled the instant the owning provider is disposed, and the sleep
/// reports whether it was cut short, so the loop returns instead of
/// scheduling one more.
class PollClock {
  /// Hand it `ref.onDispose`; the clock registers itself, so a provider only
  /// writes `final PollClock clock = PollClock(ref.onDispose);` at the top of
  /// its build. Riverpod runs those callbacks both when the provider is
  /// disposed and before it is rebuilt, so a rebuild cannot leave the
  /// previous loop running.
  PollClock(void Function(void Function() listener) onDispose) {
    onDispose(stop);
  }

  Timer? _timer;
  Completer<bool>? _sleeper;
  bool _stopped = false;

  /// Whether the owner has gone. A loop that wants to check before doing
  /// expensive work can read this.
  bool get isStopped => _stopped;

  /// Waits [interval].
  ///
  /// Returns `true` if the interval elapsed normally — poll again — and
  /// `false` if the owning provider was disposed while we waited, in which
  /// case the caller must return.
  Future<bool> sleep(Duration interval) {
    if (_stopped) return Future<bool>.value(false);

    final Completer<bool> sleeper = Completer<bool>();
    _sleeper = sleeper;
    _timer = Timer(interval, () {
      _timer = null;
      _sleeper = null;
      if (!sleeper.isCompleted) sleeper.complete(true);
    });
    return sleeper.future;
  }

  /// Cancels the pending wake-up and releases the sleeping loop so it can
  /// finish. Safe to call more than once.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;

    final Completer<bool>? sleeper = _sleeper;
    _sleeper = null;
    if (sleeper != null && !sleeper.isCompleted) sleeper.complete(false);
  }
}

/// Emits [fetch] now and every [interval] until [clock] is stopped.
Stream<T> pollEvery<T>(
  PollClock clock,
  Duration interval,
  Future<T> Function() fetch, {
  bool emitErrors = true,
}) async* {
  while (true) {
    try {
      yield await fetch();
    } catch (error) {
      // A single failed poll should not kill the stream — the network drops
      // in a queue hall constantly. Surface it once, or keep trying.
      if (emitErrors) rethrow;
    }
    if (!await clock.sleep(interval)) return;
  }
}

/// Polls, but keeps the last good value when a refresh fails.
///
/// This is what the ticket screen wants: if one poll times out, the customer
/// should keep seeing their position, not an error page.
Stream<T> pollKeepingLastValue<T>(
  PollClock clock,
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
    if (!await clock.sleep(interval)) return;
  }
}
