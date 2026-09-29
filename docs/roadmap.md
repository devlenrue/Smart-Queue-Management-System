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
| Flutter | `flutter run` / `flutter build apk` | Source is written to compile against the pinned SDK and linted by eye against `flutter_lints`; it **cannot be compiled here** and must be run with `flutter pub get && flutter run` on a machine with the SDK |

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

## PHASE 5 — Customer app ◐

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

## PHASE 6 — Staff app ◐

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

## PHASE 7 — Admin ☐

**Objective.** Services, counters, staff, users, queue monitoring and announcements.

**Create.** repositories/services/controllers for `staff`, `user`, `announcement`, `counter` admin paths;
`GET /dashboard/admin`; `providers/admin_providers.dart`; `features/admin/*` (12 screens);
`widgets/app_data_table.dart`, `widgets/chart_card.dart`.

**Database.** Uses `announcements`, `system_settings`.

**API.** §54 Counters · §55 Staff · §9 Users · §11 Announcements · §12 Dashboards.

**Test.** Search and filter correctness (§40) · role matrix enforced on every admin route · queue monitor
matches the database after a scripted sequence of staff actions.

---

## PHASE 8 — Reporting ☐

**Objective.** Four SQL-aggregate reports plus the dashboard charts.

**Create.** `src/repositories/report.repository.ts`, `src/services/report.service.ts`,
`src/controllers/report.controller.ts`, `src/routes/report.routes.ts`,
`features/admin/reports/*`, `tests/reports.test.ts`.

**API.** `GET /reports/daily|services|staff|queues`.

**Flutter.** Reports tabs with date-range picker, charts, CSV export.

**Test.** Seed a known day, assert each aggregate equals a hand-computed value; assert charts render from
API data with no literals in the widget tree.

---

## PHASE 9 — Testing and hardening ☐

**Objective.** Confidence and polish.

**Work.** Raise backend coverage on `services/` to ≥ 80 % · negative-path tests for every 4xx `code` ·
loading and empty states audited on every screen (§64, §65) · responsive check at 360 / 768 / 1280 dp ·
rate limits · CORS · `helmet` · dependency audit.

**Test.** `npm test` green · `flutter test` green · the §85 success-criteria walkthrough performed
end-to-end against MySQL.

---

## PHASE 10 — Documentation ☐

**Objective.** A marker can clone, run and understand the project without asking a question.

**Create/finish.** `README.md` (all 14 sections of §76) · `docs/user-guide.md` (one walkthrough per role)
· `docs/api.md` kept in sync · `docs/architecture.md` diagrams · screenshots in `docs/screenshots/` ·
`docs/known-limitations.md`.

**Test.** Follow the README from a clean clone on a fresh machine and confirm every command works as
written.

---

## Optional extensions (only after Phase 10, §81)

☐ QR code on the ticket screen (`qr_flutter`, encodes `ticketNumber|id`)
☐ Public display board (already scaffolded as a static page in Phase 7)
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
| 5 Customer app | ☐ | widget tests + manual run |
| 6 Staff app | ◐ | `tests/staff.test.ts` (34) ☑ · Flutter awaiting a device run |
| 7 Admin | ☐ | role matrix tests |
| 8 Reports | ☐ | `tests/reports.test.ts` |
| 9 Hardening | ☐ | coverage + responsive audit |
| 10 Docs | ☐ | clean-clone dry run |
