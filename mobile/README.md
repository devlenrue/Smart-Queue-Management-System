# SmartQueue — Flutter client

The client for the Smart Queue Management System. It talks to the Express API
in [`../server`](../server) over REST; it holds no business logic of its own
and invents no data.

Phase 5 shipped the **authentication and customer** experience; Phase 6 added
the **staff console**. The admin console (Phase 7) reuses the same core,
models and widgets. Which app you land in is decided by your role: customers
start at `/home`, staff and admins at `/staff/console`.

---

## 1. Running it

This repository contains only `lib/`, `test/`, and `pubspec.yaml` — the
platform folders are generated, so they are not committed.

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

Signing in as a customer is what Phase 5 covers; the other roles land on the
customer shell until Phases 7–8 add their consoles.

---

## 2. Tests

```bash
flutter test            # all suites
flutter analyze         # static analysis
```

| Suite | What it pins down |
| --- | --- |
| `test/core/validators_test.dart` | Client rules match the server's zod schemas |
| `test/core/error_mapper_test.dart` | Every HTTP status becomes the right `Failure` |
| `test/core/formatters_test.dart` | Wait times, ordinals and relative dates read well |
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

Widget tests run against fakes of the six repositories
(`test/helpers/test_harness.dart`), so no HTTP and no platform channels are
involved.

The staff console polls for as long as it is on screen, so its tests finish
with `tester.unmountAndDrain(harness)`: that takes the tree down and pumps
once more so the last `Future.delayed` fires and the generator exits. Without
it the test would end with a timer still pending.

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
and every polling provider is `autoDispose`, so leaving a screen ends its
requests.
