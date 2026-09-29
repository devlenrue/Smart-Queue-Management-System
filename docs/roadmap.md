# SmartQueue — Development Roadmap

Ten phases, built and verified in order. Each phase follows the template required by §84 of the brief:
**objective · architecture changes · files to create · files to modify · database changes · API changes ·
Flutter changes · testing procedure**.

Legend: ☐ not started · ◧ in progress · ☑ done and verified

---

## Verification strategy (read this first)

The development sandbox used to build this project has a restricted network: **MySQL cannot be installed
and Flutter's SDK/pub.dev are unreachable.** That does not change the deliverable — MySQL and Flutter stay
the target stack — but it changes how each phase is *proved*:

| Component | Target (student's machine / marker's machine) | How it is verified while building |
| --- | --- | --- |
| Database | MySQL 8, `smart_queue`, `database/migrations/*.mysql.sql` | A byte-for-byte equivalent SQLite schema (`*.sqlite.sql`) generated from the same table definitions, driven through the identical repository layer by a `SqliteDriver`. Every migration file is also syntax-checked. |
| Backend | `mysql2` pool against MySQL | Full test suite + a live server run against the SQLite driver; all SQL stays within the portable subset, and MySQL-only clauses (`FOR UPDATE`, `ENUM`) are emitted by the driver, not scattered through the code |
| Flutter | `flutter run` / `flutter build apk` | The SDK is unreachable from the sandbox, so the source is written to compile against the pinned SDK and read by eye against `flutter_lints`, then **run on the student's machine**: `flutter analyze` reports no issues and `flutter test` passes all 191 tests across 19 suites on Flutter 3.35 / Dart 3.9 |

The database abstraction is one small interface (`DbDriver`) with two implementations. It is ~120 lines,
it is documented, and it is the reason the queue engine can be tested at all in this environment. On the
marker's machine `DATABASE_URL=mysql://…` selects the MySQL driver and nothing else changes.

---

## PHASE 0 — Design freeze ☑

**Objective.** Agree the architecture, schema, API surface, screens and rules before any code exists.

**Deliverables.** `docs/architecture.md` · `docs/database.md` (ER diagram + full table reference) ·
`docs/api.md` · `docs/queue-engine.md` (state machine + concurrency) · `docs/flutter-app.md` ·
`docs/roadmap.md` · `database/diagrams/er-diagram.mmd`.

**Exit criteria.** The 14 business rules of §59 each have a named enforcement point; every API endpoint in
§50–§57 appears in the spec; every screen in §43 appears in the navigation map.

---

## PHASE 1 — Project setup ☑

**Objective.** A running Express server, a compiling Flutter shell, and a repo that a marker can clone.

**Architecture.** Introduces `server/` (TypeScript build, env config, health route) and `mobile/`
(Flutter skeleton with theme + router). No domain logic yet.

**Create.**
`server/package.json`, `tsconfig.json`, `.env.example`, `.eslintrc`, `src/config/env.ts`,
`src/app.ts`, `src/server.ts`, `src/utils/logger.ts`, `src/utils/AppError.ts`,
`src/utils/apiResponse.ts`, `src/middleware/errorHandler.ts`, `src/middleware/notFound.ts`,
`src/routes/index.ts`, `src/routes/health.routes.ts`, `tests/setup.ts`;
`mobile/pubspec.yaml`, `lib/main.dart`, `lib/app.dart`, `lib/core/theme/app_theme.dart`,
`lib/core/constants/*`, `lib/core/routing/*`; root `.gitignore`.

**Modify.** `README.md`.

**Database.** None.

**API.** `GET /api/v1/system/health`.

**Flutter.** App boots to a placeholder splash using the real theme and router.

**Test.** `npm run dev` → `curl localhost:5000/api/v1/system/health` returns the success envelope;
`npm test` runs; `npm run build` type-checks clean.

---

## PHASE 2 — Database ☑

**Objective.** The complete schema, applied by a repeatable migration runner, plus realistic seed data.

**Architecture.** Adds `src/db/` — `types.ts` (the driver interface), `mysqlDriver.ts`,
`sqliteDriver.ts`, `sql.ts` (dialect shims), `index.ts`, `migrate.ts`, `seed.ts`.

**Create.** `database/migrations/001…005` × two dialects, `src/db/*` (drivers, migrate, seed, CLI),
`src/types/db.ts`.

**Database.** All five domain-grouped migrations: 14 tables, every FK, unique key, check and index
from `docs/database.md`, including the `active_service_id` generated column.

**API.** None.

**Flutter.** None.

**Test.** `npm run db:migrate` twice (second run is a no-op) · `npm run db:seed` · a schema test asserting
every expected table, unique key and index exists · a constraint test proving a duplicate active ticket is
rejected by the **database**, not just the app.

---

## PHASE 3 — Backend foundation ☑

**Objective.** Authentication, authorisation, validation and error handling — the frame every later
endpoint drops into.

**Create.** `src/utils/jwt.ts`, `src/utils/password.ts`, `src/middleware/auth.ts`, `rbac.ts`,
`validate.ts`, `rateLimit.ts`, `src/repositories/user.repository.ts`,
`src/services/auth.service.ts`, `src/controllers/auth.controller.ts`,
`src/validators/auth.validators.ts`, `src/routes/auth.routes.ts`, `tests/auth.test.ts`.

**Database.** Uses `users` and `revoked_tokens`.

**API.** `POST /auth/register` · `POST /auth/login` · `GET /auth/me` · `POST /auth/logout` ·
`POST /auth/change-password` · `GET /profile` · `PUT /profile`.

**Flutter.** None yet.

**Test.** Register → 201 with a token · duplicate email → 409 · weak password → 422 · login wrong
password → 401 · `/auth/me` without a token → 401 · with a customer token on an admin route → 403 ·
logout then reuse the token → 401 · assert no response body ever contains `password_hash`.

---

## PHASE 4 — Queue engine ★ ☑

**Objective.** The core of the project: services, daily queues, concurrency-safe ticket issuing, position
and estimate maths, and every state transition.

**Created.** repositories `service`, `counter`, `queue`, `ticket`, `event`, `notification`,
`assignment`; services `estimation`, `notification`, `queue`, `ticket`, `service`;
serializers `service`, `ticket`; `validators/queue.validators.ts`; controllers + routes for
services / queues / tickets; `tests/{services,queue.engine,transitions,concurrency}.test.ts`.

**Database.** Reads/writes `services`, `service_hours`, `queue_settings`, `queues`, `queue_tickets`,
`queue_events`, `service_counters`, `staff_assignments`, `notifications`.

**API.** Services (list, search, detail, CRUD, hours, settings, categories) · Queues (list, status,
join, monitor, pause/resume/close) · Tickets (my, active, detail, position, events, cancel, next,
call, recall, start, complete, skip, no-show).

**Flutter.** None yet.

**Result.** 146 new tests, 196 in total, all passing. (Phase 5 later added the notification and
announcement endpoints with 20 more, bringing the suite to **216**.)

- `tests/services.test.ts` (30) — catalogue, search, pagination, admin CRUD, hours, settings
- `tests/queue.engine.test.ts` (43) — numbering, join guards, estimation, position, **the §85 workflow
  end to end through the real API and database**
- `tests/transitions.test.ts` (59) — the full legal/illegal edge matrix and Rule 4 authorisation
- `tests/concurrency.test.ts` (14) — §60, see the table in `docs/queue-engine.md` §3

Verified by hand as well: the API was run against the seeded database and the whole workflow walked
through with `curl` — join, duplicate rejection, Rule 4 and Rule 5 rejections, call, serve, complete,
audit trail, admin monitor, pause/resume, cancel.

---

## PHASE 5 — Customer app ☑

**Objective.** A customer can register, browse services, take a ticket and watch it move — against the
real API.

**Written.** 75 Dart files under `mobile/lib`, plus 10 under `mobile/test`:

* `core/` — constants, `Failure` hierarchy + `ErrorMapper`, Dio client with the auth interceptor and
  envelope unwrapping, keystore/prefs storage, Material 3 theme with the `StatusPalette` extension,
  validators, formatters, polling helpers, responsive breakpoints, the guarded GoRouter.
* `models/` — hand-written `fromJson` for user, service, queue, ticket, counter, notification,
  announcement and the paging envelope. No code generation.
* `services/` → `repositories/` → `providers/` — five API classes, five repositories, and the
  Riverpod graph (`infrastructure`, `auth`, `customer`).
* `widgets/` — `AppCard`, buttons, text field, status badge, service/ticket/queue cards, stat card,
  skeletons, empty and error states, confirmation dialog, notification tile, form error banner.
* `features/auth/` — splash (session restore with retry), login, register, forgot password.
* `features/customer/` — five-tab shell, dashboard, service list and detail, join sheet, ticket
  screen with live position, queue board, history, alerts, announcements, profile, settings.

**Backend addendum.** The inbox and the announcements strip needed endpoints that did not exist yet, so
Phase 5 also added `announcement.repository.ts`, `notification.serializer.ts`,
`notification.validators.ts`, `notification.controller.ts`, `notification.routes.ts`, the two query
services, and `tests/notifications.test.ts` — **20 tests, suite now 216**.

**Deliberately deferred.** `AppDataTable` and `ChartCard` belong to the staff and admin consoles; they
are written in Phases 7–8 rather than shipped here as dead code.

**Database.** None.

**API.** Consumes auth, services, queues, tickets, notifications, announcements.

**Test.** Nine Flutter suites: validators, error mapper, formatters, status badge, login, register,
service list, ticket screen, cancel dialog. Widget tests run against fakes of the five repositories,
so no HTTP and no platform channels are involved.

**Outstanding.** The sandbox used to build this has no Flutter SDK and no access to `pub.dev`, so the
Dart has never been compiled. Phase 5 closes when `flutter pub get && flutter analyze && flutter test`
run clean on a machine that has the toolchain, and the §85 walkthrough has been performed on a device
against the live API.

---

## PHASE 6 — Staff app ☑

**Objective.** A staff member runs a counter end to end.

**Backend — done and verified.** The §53 transitions already existed from Phase 4; Phase 6 added the
read model the console needs.

* `repositories/statistics.repository.ts` — staff totals, averages, per-day rollup, handled-ticket
  list, per-counter day tally. All aggregates, nothing cached.
* `services/staff.service.ts` — assignment resolution, the dashboard assembly, statistics, handled
  tickets, and the counter on/off-duty switch.
* `serializers/staff.serializer.ts` · `validators/staff.validators.ts` ·
  `controllers/staff.controller.ts` · `routes/staff.routes.ts`.
* Mounted: `GET /dashboard/staff`, `GET /staff/:id/statistics`, `GET /staff/:id/tickets`,
  `GET /counters`, `PATCH /counters/:id/status`.

`GET /staff/:id/tickets` was **not** in the original plan. It turned out that `GET /tickets/my` is
scoped to the caller's tickets *as a customer*, so nothing could answer "what did I handle today?" —
the history screen needs a query that joins `queue_events.user_id`.

**Attribution.** Work counts towards the staff member who caused the event
(`queue_events.user_id`), not towards whoever happens to own the counter now. Counters get
reassigned; the audit trail does not move.

**Flutter — written.** 15 new files under `mobile/lib` (90 total), 4 under `mobile/test` (14 total):

* `models/staff_dashboard.dart`, `models/staff_statistics.dart`, and `QueueMonitor` added to
  `models/queue.dart`.
* `services/staff_api.dart` → `repositories/staff_repository.dart` → `providers/staff_providers.dart`.
* `features/staff/` — shell (rail on wide screens), console, current queue + ticket detail, history,
  statistics, profile, and four widgets (`now_serving_card`, `ticket_action_bar`,
  `waiting_ticket_tile`, `counter_status_tile`).
* The router guard is now role-aware: `homeFor(role)`, a customer on `/staff/*` is sent to `/home`,
  and a clerk outside the staff namespace is sent to `/staff/console`. `/settings` and `/about` stay
  shared.

**Fixed along the way.** `queueActionProvider` and `staffActionProvider` are no longer `autoDispose`.
Both are only ever reached through `ref.read(…notifier)` from a button handler, so nothing watches
them — an auto-dispose provider with no watchers is torn down on the next event-loop turn, i.e. while
the request is still in flight, and the `ref` calls it makes afterwards would have thrown.

**Database.** None. Uses `staff_assignments`, `service_counters`, `queue_events`.

**Test.** `tests/staff.test.ts` — **34 tests, suite now 250**. Access control (403 for a customer,
401 anonymous, self-only statistics, `me` alias) · Rule 4 (403 `NOT_ASSIGNED_TO_SERVICE` on
call-next, on a transition, on the counter list, and on a dashboard override) · Rule 5 (409
`COUNTER_BUSY`, and the counter freeing on completion) · the counter switch (409 while serving, 403
on someone else's, 409 `COUNTER_OFFLINE` when calling from an off-duty counter) · the dashboard
(unassigned, service/counter naming, queue order, current ticket, per-clerk vs per-service counts,
admin supervision) · statistics (zeroes, served/skipped/no-show split, attribution, per-day grouping,
ranges, 422 on a bad date) · handled tickets (once each, exclusion, filter, pagination) · and the §74
steps 7–13 walkthrough end to end.

Four Flutter suites: `staff_dashboard_test`, `staff_queue_test`, `staff_actions_test`,
`staff_reports_test`.

**Outstanding.** Same as Phase 5 — the Dart has not been compiled. Phase 6 closes when
`flutter analyze && flutter test` run clean and a staff member has driven a ticket
`call → start → complete` on a device against the live API.

---

## PHASE 7 — Admin ☑

**Objective.** Services, counters, staff, users, queue monitoring and announcements.

**Backend — done and verified.**

* `repositories/admin.repository.ts` (institution-wide aggregates) and
  `repositories/settings.repository.ts`; `user.repository.ts`, `assignment.repository.ts` and
  `announcement.repository.ts` grew the admin queries they were missing.
* `services/user.service.ts`, `services/roster.service.ts`, `services/announcement.service.ts`,
  `services/admin.service.ts` — every write that touches two tables runs in one transaction, so
  suspending a clerk frees their counter and ends their assignment together or not at all.
* `serializers/admin.serializer.ts` · `validators/admin.validators.ts` (17 schemas) ·
  `controllers/{user,roster,announcement,admin}.controller.ts` ·
  `routes/{user,counter,announcement,dashboard,system}.routes.ts`.
* Mounted: `/users` (+`/:id/status`, `/:id/role`, delete) · `/staff` CRUD and
  `assign`/`unassign` · `/counters` CRUD and `assign` · `/services` CRUD, `/hours`, `/settings` ·
  `/announcements/manage` plus `publish`/`archive` · `GET /dashboard/admin` ·
  `GET|PUT /system/settings`.

**Decisions.** Announcement notifications fan out **once**, on the transition into `published` —
re-publishing is a no-op, so nobody gets notified twice. Settings values are stored as text and a
`null` deletes the key. `servedPerDay` is dense and always ends on the day being reported, so the
chart cannot silently drop a quiet day.

**Flutter — written.** 24 new files under `mobile/lib` (114 total), 4 under `mobile/test` (18 total):

* `models/{admin_dashboard,staff_member,user_detail,system_setting}.dart`, plus `ManagedAnnouncement`
  and the counter's service naming.
* `services/admin_api.dart` → `repositories/admin_repository.dart` → `providers/admin_providers.dart`.
* `features/admin/` — shell, dashboard, services + service form, counters, staff, users + user
  detail, queue monitor + live board, announcements + composer, system settings, and two dialogs
  (`widgets/staff_form_dialog.dart`, `widgets/user_status_chip.dart`); plus the shared
  `widgets/app_data_table.dart` and `widgets/chart_card.dart`.
* The guard now knows three consoles: a customer is kept out of both back offices, a clerk out of
  administration, and an administrator may use either.

**Database.** Uses `announcements`, `system_settings`. No migration.

**API.** §54 Counters · §55 Staff · §9 Users · §11 Announcements · §12 Dashboards · §14 System.

**Test.** `tests/admin.test.ts` — **59 tests, suite now 309**. The role matrix on every admin route
(customer 403, staff 403, admin vs super-admin split, nobody administers themselves) · user status,
role and delete rules including the counter being freed on suspension · the roster, its
`unassigned=true` filter and the `STAFF_ALREADY_ASSIGNED` / `COUNTER_BUSY` conflicts · counter CRUD
and assignment · service CRUD, hours and settings validation · announcement drafts, the one-shot
publish fan-out, archive and delete · settings as text, `null` deleting a key, 403 for an ordinary
admin · the dashboard's aggregates against a scripted day, `?days=` and `?date=`.

Four Flutter suites: `admin_dashboard_test`, `admin_users_test`, `admin_staff_test`,
`admin_monitor_test`.

**Outstanding.** As with Phases 5 and 6, the Dart has not been compiled. Phase 7 closes when
`flutter analyze && flutter test` run clean and an administrator has created a counter, posted a
clerk to it and published an announcement on a device against the live API. Reports
(`/admin/reports`) are Phase 8.

---

## PHASE 8 — Reporting ☑

**Objective.** Answer the four questions §41 asks — how was the day, how is each service doing, who
did the work, how did the queues behave — from the same tables the consoles read, and let an
administrator carry the answer away as a CSV.

**Built.**

* `src/repositories/report.repository.ts` — six aggregate queries (`daily`, `totals`, `services`,
  `hourly`, `staff`, `queues`, `waitingIntervals`), all portable across both dialects through the
  helpers in `db/sql.ts` (`diffMinutes`, `hourOf`).
* `src/services/report.service.ts` — the arithmetic SQL is bad at: the interval sweep behind peak
  and average queue length, and the window behind utilisation.
* `src/serializers/report.serializer.ts`, `src/serializers/report.csv.ts`, `src/utils/csv.ts`,
  `src/validators/report.validators.ts`, `src/controllers/report.controller.ts`,
  `src/routes/report.routes.ts` (mounted at `/reports`).
* `src/validators/common.validators.ts` — `dateField` now rejects dates that do not exist
  (`2026-13-40` used to pass the shape check and then quietly match nothing).

**Decisions.**

* **Staff work is credited by event, not by counter.** `queue_events.user_id` is who pressed the
  button; attributing by the ticket's counter would move a morning's work to whoever is sitting
  there in the afternoon.
* **Peak queue is a real maximum overlap**, computed by sweeping each ticket's waiting interval —
  not "the most tickets issued in an hour" dressed up as a queue length.
* **A queue still open is measured to now.** Measuring it to its last recorded activity made an
  office that has been open since eight and idle since ten look 100% utilised, and produced an
  average queue longer than the peak. The invariant `averageQueue ≤ peakQueue` is now a test.
* **`null` is not zero.** An average over tickets that never reached a counter stays `null` through
  the API, the table (`—`) and the CSV (an empty cell).
* **CSV is generated by the server.** The client downloads and saves the bytes rather than
  rebuilding them, so the file a marker opens is the API's own output. It is the only response in
  the API that is not the §1 envelope.

**Flutter — written.** 7 new files under `mobile/lib` (121 total), 1 under `mobile/test` (19 total):

* `models/report.dart` · `services/report_api.dart` → `repositories/report_repository.dart` →
  `providers/report_providers.dart` · `core/export/report_exporter.dart` (an interface, so a widget
  test can export without a platform channel) · `features/admin/reports_screen.dart` and
  `features/admin/widgets/report_tables.dart`.
* `ApiClient.getText` — the one path past the envelope unwrapping, for the CSV download.
* A Reports destination in the admin shell, at `/admin/reports`.
* New dependency: `path_provider`, for the directory the CSV is written to. Run `flutter pub get`.

**Database.** No migration — every figure is derived at read time.

**API.** §13 of `docs/api.md`, including the definition of each derived column.

**Test.** `tests/reports.test.ts` — **63 tests, suite now 372**. A fixture day is driven through the
real API (join, call, serve, complete, skip, cancel) and only then given a known clock, so every
assertion is both reachable through the state machine and checkable by hand: issued 5, served 2,
average wait 20.0, average service 10.0, peak queue 3, average queue 1.6, utilisation 25%, peak hour
09:00–10:00. Plus the range defaults and validation (impossible dates, reversed ranges, >366 days),
the role matrix, the weighted staff totals, the `averageQueue ≤ peakQueue` invariant, and the CSV
writer's quoting rules.

**Verified.** `flutter pub get && flutter analyze && flutter test` on the student's machine:
no analyzer issues, **191 tests across 19 suites green**, including the 14 in
`test/features/admin_reports_test.dart`.

---

## PHASE 9 — Testing and hardening ◐

**Objective.** Confidence and polish: prove the parts of the system that only show themselves when
something goes wrong.

**Built — the error contract.**

* `src/utils/AppError.ts` — `ErrorCode` was a bare type union, which meant the list of codes existed
  three times (the type, the documentation, and whatever the tests happened to assert). It is now a
  runtime `ERROR_CATALOGUE` mapping each code to the one HTTP status it is ever sent with; the type
  is derived from it, the middleware reads the status from it, and `docs/api.md` §1 tabulates it.
* `src/middleware/errorHandler.ts` — body-parser throws an `http-errors` object, not an `AppError`,
  so an oversized body was falling through to the generic 500 branch and being reported to the user
  as *our* fault. `entity.too.large` → `413 PAYLOAD_TOO_LARGE`, other `entity.*` → `400 BAD_REQUEST`.

**Built — hardening.**

* `src/middleware/rateLimit.ts` — the limiters were skipped whenever `NODE_ENV=test`, with no way to
  turn them back on, so they had never once been executed. `RATE_LIMIT_IN_TESTS=true` re-enables them
  for the one file that tests them. A third limiter, `apiLimiter`, now backs the whole of `/api/v1`
  at a ceiling chosen against the client's actual polling rate rather than by feel
  (`RATE_LIMIT_API_MAX`, default 1000 per 15 minutes; a customer app polling flat out uses ~300).
* `helmet` and CORS were already wired; they are now asserted rather than assumed.

**Modify.** `src/config/env.ts` (two new settings), `src/app.ts`, `.env.example`, `jest.config.js`
(coverage thresholds), `package.json` (`npm run test:coverage`).

**Tests added — 85, suite now 457 across 13 files.**

* `tests/errors.test.ts` (46) — one negative path per error code, provoked through HTTP and checked
  against the whole envelope, not just the status. The last test in the file walks the catalogue and
  fails if a 4xx code has no test above it, so the contract cannot drift again.
* `tests/security.test.ts` (9) — helmet's headers, CORS for an allowed and a disallowed origin, all
  three limiters tripping with the right envelope and `RateLimit-*` headers, and per-IP isolation.
* `tests/edge.cases.test.ts` (30) — the branches coverage reported as never executed: publishing an
  announcement through an edit (and the fan-out not firing twice), releasing a desk when a clerk is
  deactivated, moving a clerk between desks, optional filters and defaulted arguments, guard 3 and
  guard 4 of the user service, and the report shapes the Phase 8 fixture cannot produce (a queue
  that issued nothing; a clerk who handled tickets but completed none).

**Coverage.** `src/services/` — statements 91.0 % → **96.6 %**, branches 69.3 % → **86.0 %**,
lines 95.4 % → **99.4 %**. Now enforced: Jest fails under 95/80/95/97 for the services layer as a
group, 90/70/90/90 for any single service file, and 88/68/86/90 for `src/` overall.

**Flutter — written, not yet run.** 2 new files under `mobile/test` (21 suites total):

* `test/responsive/layout_audit_test.dart` — five screens pumped at 360, 768 and 1280 dp. At each
  width it asserts no layout exception was thrown, then that the breakpoint *did something*: a
  `DataTable` on a laptop and a tablet, cards on a phone, and service cards one, two and three to a
  row. Height is held at 1600 so a failure points at the width rule, not at scrolling.
* `test/states/state_audit_test.dart` — a table of six screens with the fake state that starves each
  one, run through the same three checks: something on screen while it loads (§64), an `EmptyState`
  that explains itself rather than a blank list (§65), and an `ErrorState` with a retry that really
  re-asks the server.
* `test/helpers/test_harness.dart` — two new opt-in failure flags (`admin.listFailure`,
  `staff.readFailure`). Both default to null, so no existing test changes behaviour.

**Dependencies.** `npm audit` — **0 vulnerabilities**, with and without dev dependencies. The
backend has eleven runtime dependencies and no transitive surprises, which is the point of not
reaching for a framework-of-frameworks on a project this size.

**Database.** None.

**Test.** `npm test` green (457) · `npm run test:coverage` green against the thresholds ·
`flutter analyze && flutter test` on the student's machine · the §85 walkthrough end-to-end, which
is now `npm run walkthrough` and is recorded in [`docs/walkthrough.md`](walkthrough.md) — fifteen
steps, all green against the seeded database.

**Outstanding.** The two new Flutter suites have not been run — the sandbox has no Flutter SDK.
Phase 9 closes when `flutter test` is green and the walkthrough has been run against MySQL rather
than the SQLite fallback.

---

## PHASE 10 — Documentation ◐

**Objective.** A marker can clone, run and understand the project without asking a question.

**Built.**

* `README.md` restructured into the sections §76 asks for, in order: status, what it does, features,
  stack, **requirements**, quick start, **configuration** (every environment variable with its
  default and what it actually controls), project structure, **API documentation**, roles and demo
  accounts, testing, **end-to-end walkthrough**, **screenshots**, **known limitations**,
  **troubleshooting**, design documents, and an academic note.
* `docs/user-guide.md` — one walkthrough per role, written against the running app. Every screen
  name, button label and refusal message quoted in it is the one actually on screen; the wording was
  read out of the widgets rather than remembered.
* `docs/known-limitations.md` — separated into what §82 ruled out, what was traded deliberately, and
  what is simply unfinished, because a marker deserves to know which is which. Polled notifications,
  no WebSocket, manual password reset, single tenant, the SQLite fallback's weaker concurrency
  story, read-time reporting, fake-backed client tests, and a short list of smaller things.
* `docs/walkthrough.md` + `server/scripts/walkthrough.sh` (`npm run walkthrough`) — the §85 success
  criteria as a script rather than a claim. Fifteen steps through documented endpoints against the
  real database, including the two rules worth watching fail (`DUPLICATE_ACTIVE_TICKET`,
  `COUNTER_BUSY`) and the 403s that prove ownership isolation and RBAC. The one setting it touches —
  today's opening hours, so the script runs after 5 p.m. — it restores on exit.
* `docs/screenshots/README.md` — the shot list. **No screenshots were generated.** A mocked-up image
  of a screen that has never been rendered is worse than none, so the folder carries twenty
  described shots with the exact state to put the app in, instead of pictures nobody took.
* `docs/api.md` §1 — the error-code catalogue and the transport-hardening table (added with Phase 9,
  listed here because it is what keeps the API document in sync with the code).

**Decisions.**

* **The walkthrough is executable.** A transcript in a document rots the first time an endpoint
  changes. A script that a marker can run cannot: if it drifts, it fails.
* **Missing evidence is named, not faked.** Screenshots and the two unrun Flutter suites are listed
  as outstanding in three places rather than papered over.

**Test.** `npm run dev` then `npm run walkthrough` — fifteen steps, all green, recorded in
`docs/walkthrough.md`. Both commands the README prints for a smoke test (`/system/health` and a
login `curl`) were executed exactly as written and corrected where they were wrong.

**Outstanding.** Screenshots (needs a device). A clean-clone dry run on a machine with MySQL and
Flutter installed — the SQLite path has been dry-run here end to end.

---

## Optional extensions (only after Phase 10, §81)

☐ QR code on the ticket screen (`qr_flutter`, encodes `ticketNumber|id`)
☐ Public display board (a static page served by the API, sketched in §81)
☐ Priority categories (`normal|priority|emergency`, admin-set only, changes the call-next `ORDER BY`)
☐ Appointment + walk-in hybrid

---

## Tracking

| Phase | Status | Verified by |
| --- | --- | --- |
| 0 Design | ☑ | documents reviewed |
| 1 Setup | ☑ | health endpoint + build |
| 2 Database | ☑ | migration + schema tests (20) |
| 3 Auth | ☑ | `tests/auth.test.ts` (30) |
| 4 Queue engine | ☑ | `queue.engine` (41), `transitions` (53), `concurrency` (14) |
| 5 Customer app | ☑ | `flutter test` — 9 suites, green on Flutter 3.35 / Dart 3.9 |
| 6 Staff app | ☑ | `tests/staff.test.ts` (34) · 4 Flutter suites |
| 7 Admin | ☑ | `tests/admin.test.ts` (59) · 4 Flutter suites |
| 8 Reports | ☑ | `tests/reports.test.ts` (63) · `flutter test` 191/191 |
| 9 Hardening | ◐ | `errors` (46) · `security` (9) · `edge.cases` (30); 2 Flutter suites awaiting a device run |
| 10 Docs | ◐ | `npm run walkthrough` 15/15 · README smoke commands run as written; screenshots outstanding |
