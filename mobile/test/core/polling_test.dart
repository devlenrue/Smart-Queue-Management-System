import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/utils/polling.dart';

/// The one piece of machinery every polled screen sits on (§70).
///
/// These are `testWidgets` rather than plain `test` cases for one specific
/// reason: the widget tester runs the body in a fake-async zone and asserts
/// at the end that no timer is still pending. That assertion *is* half of
/// what is being tested here — a clock that forgets to cancel its wake-up
/// fails these tests by leaking, exactly as a leaking screen would.
void main() {
  testWidgets('a completed interval reports a normal wake-up',
      (WidgetTester tester) async {
    // Nothing ever disposes this one; it just runs its course.
    final PollClock clock = PollClock((void Function() _) {});

    bool? woke;
    unawaited(clock.sleep(const Duration(seconds: 5)).then((bool v) => woke = v));

    await tester.pump(const Duration(seconds: 5));

    expect(woke, isTrue, reason: 'the loop should go round again');
  });

  testWidgets('stopping the clock wakes the sleeper and cancels the timer',
      (WidgetTester tester) async {
    late void Function() dispose;
    final PollClock clock = PollClock((void Function() cb) {
      dispose = cb;
    });

    bool? woke;
    unawaited(clock.sleep(const Duration(seconds: 5)).then((bool v) => woke = v));

    // What Riverpod does the moment the screen leaves the tree.
    dispose();
    await tester.pump();

    expect(woke, isFalse, reason: 'the loop should return, not poll again');
    expect(clock.isStopped, isTrue);
    // If stop() had left the five-second timer running, this test would now
    // fail with "A Timer is still pending even after the widget tree was
    // disposed" — which is the failure this class exists to prevent.
  });

  testWidgets('a stopped clock never schedules another wake-up',
      (WidgetTester tester) async {
    late void Function() dispose;
    final PollClock clock = PollClock((void Function() cb) {
      dispose = cb;
    });

    // Disposed first, asked to sleep afterwards: this is the zombie case,
    // where a poll fails after disposal and the loop skips its `yield` and
    // heads straight back to sleep.
    dispose();

    bool? woke;
    unawaited(clock.sleep(const Duration(seconds: 5)).then((bool v) => woke = v));
    await tester.pump();

    expect(woke, isFalse);
  });
}
