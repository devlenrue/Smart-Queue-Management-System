# SmartQueue — Flutter client

The client for the Smart Queue Management System. It talks to the Express API
in [`../server`](../server) over REST; it holds no business logic of its own
and invents no data.

Phase 5 shipped the **authentication and customer** experience, Phase 6 the
**staff console**, and Phase 7 the **administrator console** — all three on
the same core, models and widgets. Which app you land in is decided by your
role: customers start at `/home`, clerks at `/staff/console`, administrators
at `/admin/dashboard`. An administrator can also open the staff console, and
the server lets them work any desk.

---

## 1. Running it

This repository contains only `lib/`, `test/`, and `pubspec.yaml` — the
platform folders are generated, so they are not committed.

**Flutter 3.35 or newer** (Dart 3.9). The app uses `Color.withValues`,
`RadioGroup` and `DropdownButtonFormField.initialValue`, each of which
replaced an API deprecated during 2025; on an older SDK `pub get` will say
so rather than failing later with a wall of analyzer output.

```bash
cd mobile

# 1. generate android/ ios/ web/ … for your machine
flutter create .

# 2. dependencies
flutter pub get

# 3. start the API first (in another terminal)
#    cd ../server && npm run dev        → http://localhost:5000

# 4. run
flutter run
```

### Pointing the app at your server

`AppConstants.apiBaseUrl` defaults to `http://10.0.2.2:5000/api/v1`, which is
how the **Android emulator** reaches `localhost` on the host machine.
Anything else needs an override:

| Target | Command |
| --- | --- |
| Android emulator | `flutter run` (default) |
| iOS simulator / desktop | `flutter run --dart-define=API_BASE_URL=http://localhost:5000/api/v1` |
| Physical phone on Wi‑Fi | `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:5000/api/v1` |

The address currently in use is shown on the login screen and under
**Settings → Connection**, so a misconfigured build is obvious immediately.

Android also needs cleartext HTTP for a plain `http://` dev server; add
`android:usesCleartextTraffic="true"` to the `<application>` tag in
`android/app/src/main/AndroidManifest.xml` after `flutter create .`.

### Demo accounts

All seeded users share the password `Password123!`:

| Role | Email |
| --- | --- |
| Customer | `john.doe@smartqueue.test` |
| Staff | `jane.staff@smartqueue.test` |
| Admin | `admin@smartqueue.test` |
| Super admin | `super@smartqueue.test` |

Each account lands in its own console. An administrator also gets Reports
(`/admin/reports`): four management reports over any date range, with a CSV
export that saves the server's own file into the app's documents directory.

---

## 2. Tests

```bash
flutter analyze         # static analysis — no issues
flutter test            # 21 suites, 228 tests
```

Last run: **all 21 suites, 228 tests, green** on Flutter 3.35 / Dart 3.9.
Run `flutter pub get` first — Phase 8 added `path_provider`.

| Suite | What it pins down |
| --- | --- |
| `test/core/validators_test.dart` | Client rules match the server's zod schemas |
| `test/core/error_mapper_test.dart` | Every HTTP status becomes the right `Failure` |
| `test/core/formatters_test.dart` | Wait times, ordinals and relative dates read well |
| `test/core/polling_test.dart` | A disposed provider cancels its pending poll instead of leaking a timer |
| `test/widgets/status_badge_test.dart` | Each status has its own colour, icon and word |
| `test/features/login_screen_test.dart` | Validation, server errors, field-level 422s |
| `test/features/register_screen_test.dart` | No role selector; mismatches caught locally |
| `test/features/service_list_test.dart` | Server-side search, disabled Join, empty states |
| `test/features/ticket_screen_test.dart` | Live position updates between polls |
| `test/features/cancel_dialog_test.dart` | Cancelling always needs confirmation |
| `test/features/staff_dashboard_test.dart` | The console: stats, up-next, Call Next and every reason it is unavailable |
| `test/features/staff_queue_test.dart` | The waiting list and the per-row Call |
| `test/features/staff_actions_test.dart` | Which transitions each ticket state offers, and the skip confirmation |
| `test/features/staff_reports_test.dart` | Statistics totals and chart, history filters |
| `test/features/admin_dashboard_test.dart` | Institution figures, both charts, the busiest service, and what the rail shows which role |
| `test/features/admin_users_test.dart` | Server-side search and filters, suspension, and who is allowed to administer whom |
| `test/features/admin_staff_test.dart` | The roster and its postings, releasing a clerk, creating one, and counter validation |
| `test/features/admin_monitor_test.dart` | The read-only live board, the announcement composer's publish warning, and the settings editor |
| `test/features/admin_reports_test.dart` | The four report tabs, the date presets and service filter reaching the server, and the CSV export writing the server's own bytes |
| `test/responsive/layout_audit_test.dart` | Five screens survive 360, 768 and 1280 dp, and the breakpoints actually switch the layout |
| `test/states/state_audit_test.dart` | Six screens show a loading affordance, a self-explaining empty state, and an error state whose retry really re-asks the server |

Widget tests run against fakes of the eight repositories
(`test/helpers/test_harness.dart`), so no HTTP and no platform channels are
involved. Two of the fakes take an optional failure — `admin.listFailure`,
`staff.readFailure` — which is how the state audit reaches an error screen
without a network. The CSV export is the one feature that would touch a channel, so it
writes through a `ReportExporter` interface that the harness replaces with an
in-memory fake.

Both back offices poll for as long as they are on screen, so their tests
finish with `tester.unmountAndDrain(harness)`: that takes the tree down and
pumps a full interval, which fails loudly right there if a poll loop ever
outlives its screen. It normally has nothing to do — every loop sleeps on a
`PollClock` (`lib/core/utils/polling.dart`) that the provider cancels in
`ref.onDispose`. The admin dashboard polls at three times the shared
interval, so its tests pass that interval in
(`unmountAndDrain(harness, interval: …)`). A staff action does the same
thing indirectly: completing a ticket refreshes the console, which starts
polling, so those tests end the same way. SnackBars need no help at all —
`ScaffoldMessengerState.dispose` cancels its own dismissal timer when the
tree goes.

---

## 3. Layout

```
lib/
├── main.dart                  entry point; loads SharedPreferences, injects it
├── app.dart                   MaterialApp.router, themes, text-scale clamp
├── core/
│   ├── constants/             endpoints, tunables, enum mirrors
│   ├── errors/                Failure hierarchy + the DioException mapper
│   ├── network/               Dio setup, interceptors, envelope unwrapping
│   ├── routing/               route paths and the guarded GoRouter
│   ├── storage/               JWT in the keystore, preferences in prefs
│   ├── theme/                 Material 3 theme + StatusPalette extension
│   └── utils/                 validators, formatters, polling, responsive
├── models/                    hand-written fromJson for every DTO
├── services/                  one class per endpoint group (HTTP only)
├── repositories/              composition + persistence over the services
├── providers/                 Riverpod wiring and screen state
├── widgets/                   the shared widget library
└── features/
    ├── auth/                  splash, login, register, forgot password
    ├── customer/              shell, dashboard, services, ticket, queue,
    │                          history, alerts, announcements, profile,
    │                          settings
    ├── staff/                 shell, console, current queue, ticket detail,
    │                          history, statistics, profile
    └── misc/                  about, 404
```

### The rules this structure exists to keep

- **Widgets never call HTTP.** A screen reads a provider; the provider asks a
  repository; the repository asks a service class; only that class knows Dio.
- **Widgets never see a `DioException`.** `ErrorMapper` converts everything
  into a `Failure` with a message already fit to show a human.
- **Nothing is computed that the server already computes.** Positions, wait
  estimates and ticket numbers are displayed, never derived.
- **No code generation.** `fromJson` is written by hand and Riverpod is used
  without `riverpod_generator`, so the source you read is the source that
  runs.

---

## 4. How "live" works

There are no websockets and no push notifications — §82 rules both out.
"Live" means a timer re-reads the server:

| Screen | Endpoint | Interval |
| --- | --- | --- |
| Ticket / dashboard ticket panel | `GET /tickets/:id/position` | 5 s (adjustable in Settings) |
| Queue board | `GET /queues/:id/status` | 10 s |
| Unread badge | `GET /notifications/unread-count` | 30 s |
| Staff console | `GET /dashboard/staff` | 10 s |

The ticket loop stops itself the moment the ticket reaches a terminal state,
and every polling provider is `autoDispose` and sleeps on a `PollClock`, so
leaving a screen cancels the pending wake-up as well as the requests.
