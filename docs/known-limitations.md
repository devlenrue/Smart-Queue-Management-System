# Known limitations

An honest list of what this system does not do, and why. Some entries are the brief's own scope
boundary (§82), some are deliberate trades, and a few are simply unfinished. They are separated
because those are three different things and a marker deserves to know which is which.

---

## 1. Out of scope by instruction (§82)

The brief rules these out. They are absent on purpose, and adding them would make the project worse,
not better.

| Not built | Why |
| --- | --- |
| M-Pesa or any payment | Taking a ticket is free. There is nothing to charge for |
| AI / ML wait prediction | The estimate is arithmetic, documented and checkable by hand (§19). A model would be unexplainable and untestable at this scale |
| Blockchain | No |
| Kubernetes, service meshes, microservices | One API process and one database. A queue for one institution does not need a distributed system, and pretending otherwise would hide the parts being marked |
| Push-notification infrastructure (FCM/APNs) | Notifications are rows in a table the client polls. See §2 below |

---

## 2. Notifications are polled, not pushed

`notifications` is a real table, written inside the same transaction as the state change that caused
it, and the client reads it every thirty seconds. That is the whole mechanism.

* **Consequence.** If the app is closed or backgrounded, the customer learns they were called when
  they next open it. In the queue hall — the actual use case — the app is open and the ticket screen
  refreshes every five seconds, so the delay is invisible.
* **Why not FCM.** A push stack is an account, a service key, a platform channel, a background
  isolate and a set of failure modes that cannot be tested in a widget test, in exchange for a
  latency improvement that this deployment cannot perceive. §82 rules it out and the trade is right.
* **What would change.** The write site is already correct: one `notificationService.create` call per
  event, inside the transaction. Pushing would mean adding a sender behind that call, nothing more.

---

## 3. No real-time transport

The three live surfaces — the customer's ticket, the staff console, the admin queue monitor — poll
on a timer (5 s / 10 s / 15 s) rather than holding a WebSocket.

* **Consequence.** A number can be up to one interval stale. Two clerks acting in the same second
  still cannot corrupt anything (the database prevents it), but the loser sees the conflict when
  their request is refused rather than the instant it becomes true.
* **Why.** Polling is visible, debuggable and needs no connection lifecycle, reconnection strategy
  or sticky sessions. Every loop sleeps on a cancellable `PollClock` and is torn down in
  `ref.onDispose`, and there is a test that fails if a loop ever outlives its screen.

---

## 4. Password reset is manual

There is no email sender, so there is no reset link. **Forgot password** says so and directs the
user to the service desk, where an administrator can set a new password after checking ID. A signed-in
user can always change their own password from **Profile → Change password**.

Adding email would mean an SMTP account, a token table and an expiry policy — a sensible extension,
but not one the brief asks for.

---

## 5. One institution per deployment

There is no tenant column. Services, counters, staff and settings all belong to "the institution",
singular. Running a second campus means a second database.

This is a deliberate simplification: multi-tenancy touches every query and every index, and would
add nothing to what is being demonstrated.

---

## 6. MySQL is the target; SQLite is the fallback

The deployment target is MySQL 8, and the schema is written for it: `InnoDB`, `SELECT … FOR UPDATE`,
generated columns, `utf8mb4`.

A parallel SQLite dialect exists so the project can be marked on a machine with no database server,
and so the test suite can build a fresh database per file in memory. Every dialect difference is
confined to `src/db/sql.ts`, and both dialects run the same migrations and the same tests.

* **Consequence.** SQLite has no `FOR UPDATE`. The fallback serialises writes with `BEGIN IMMEDIATE`
  plus an in-process mutex, which is correct for one process and would not be for two. **The
  concurrency guarantees of §60 are a MySQL claim.** They are tested on SQLite through the same code
  path, and the database-level unique keys that back them up are real on both.
* **Consequence.** `utf8mb4` collation behaviour, `TIME` handling and `ON DELETE` timing differ in
  detail. Nothing the application depends on, but a query written against SQLite alone should be
  checked on MySQL before it is trusted.

---

## 7. Reporting is computed at read time

There is no aggregate table and no nightly job. Every report figure is derived from `tickets` and
`queue_events` when it is asked for.

* **Consequence.** Reports get slower as history grows. At class-project volumes (hundreds of tickets
  a day) it is imperceptible; at a million rows the daily report would want a summary table.
* **Why.** A figure that is computed from the source can never disagree with the source. A cached one
  can, and debugging a stale aggregate is worse than waiting 40 ms.
* **Bounded.** Report ranges are capped at 366 days, so no single request can ask for everything.

---

## 8. The client's tests use fakes, not the API

Every Flutter widget test runs against a fake of the repository layer — no HTTP, no platform
channels, no server. This makes them fast and deterministic, and it means they pin down the
*client's* behaviour: what it shows while loading, what it shows when empty, what it does with a 422.

* **What they cannot catch.** A field renamed on the server without being renamed in the client. The
  seam between the two is covered by the backend's 457 tests on one side and by the client's
  serialisation tests on the other, but there is no contract test spanning both.
* **Mitigation in place.** `test/core/validators_test.dart` asserts the client's validation rules
  equal the server's zod schemas, which is where drift would hurt a user first.

---

## 9. Parts that have not been run

Written and reviewed, not executed. The sandbox this was built in has no Flutter SDK, so the Dart
could not be compiled here.

| What | State |
| --- | --- |
| `test/responsive/layout_audit_test.dart` | Written; not run |
| `test/states/state_audit_test.dart` | Written; not run |
| The §85 walkthrough against **MySQL** | Performed end-to-end against the SQLite fallback and the full test suite; not yet against a live MySQL server |
| Screenshots | Not taken — see `docs/screenshots/README.md` for the shot list |

Everything else has been run: `npm test` (457 tests, 13 suites), `npm run typecheck`,
`npm run test:coverage` against enforced thresholds, and `flutter analyze` + `flutter test`
(191 tests, 19 suites) on Flutter 3.35 / Dart 3.9.

---

## 10. Smaller things

* **The live board truncates at 50 waiting.** `getMonitor` asks for the first 50 and the counts
  beside it stay exact, so a queue of 80 shows "80 waiting" over 50 rows with no "and 30 more". The
  daily capacity setting normally keeps it under the cap; the honest fix is a paged list.
* **Deleting a user cascades.** Deactivation is the normal path and the one the console pushes you
  towards. A hard delete exists, is super-admin only, refuses your own account and refuses the last
  active super admin — but it takes that user's tickets and events with it through the foreign keys,
  which silently rewrites yesterday's report. It is there for a mis-registered account, not for
  routine use.
* **No audit log for administrators.** `queue_events` records who moved every ticket, but a role
  change or a settings edit leaves no trail beyond the row's `updated_at`.
* **No i18n.** English only, hard-coded. Strings live in the widgets rather than a message catalogue.
* **No dark-mode screenshots.** The theme supports it (Settings → Appearance); nothing documents it.
* **Times are UTC in the API, local in the app.** A deployment spanning time zones would need the
  institution's zone stored and applied to `queue_date`, which is currently the server's day.
* **`fl_chart` is a dependency but the charts are drawn by hand.** The package was pulled in early
  and then not needed; it can be removed at the next dependency pass.
