# SmartQueue — Smart Queue Management System

> A digital queue management system for institutions where people currently stand in line:
> university finance offices, registrars, admissions, clinics, libraries, banks and service centres.
>
> **Flutter** client · **Node.js + Express + TypeScript** API · **MySQL 8** database.

---

## Status

| Phase | State |
| --- | --- |
| **0 — Design** | ☑ complete — architecture, ER diagram, schema, API spec, screen map, queue state machine, roadmap |
| 1 — Project setup | ☑ complete — Express + TypeScript skeleton, config, logging, error envelope, health endpoint |
| 2 — Database | ☑ complete — 14 tables, 5 migrations × 2 dialects, deterministic seed, 20 schema tests |
| 3 — Backend foundation (auth) | ☑ complete — bcrypt + JWT, 4 roles, validation, rate limiting, 30 auth tests |
| 4 — Queue engine ★ | ☑ complete — join, ticket numbering, position, calling, serving, concurrency, 108 tests |
| 5 — Customer app | ◐ written, awaiting a device run — Flutter client: auth + 14 customer screens, 9 test suites, plus the `/notifications` and `/announcements` endpoints it needs |
| 6 — Staff app | ◐ written, awaiting a device run — staff dashboard, statistics and counter endpoints (34 tests) + a 6-screen Flutter console |
| 7 — Admin | ☐ |
| 8 — Reporting | ☐ |
| 9 — Testing | ☐ |
| 10 — Documentation | ☐ |

Full plan: [`docs/roadmap.md`](docs/roadmap.md).

---

## What the system does

```text
Customer                          Staff                        Admin
────────                          ─────                        ─────
browse services                   see the waiting queue        create services & counters
join a queue      ──ticket──►     call next                    assign staff
track position    ◄─notify───     start / complete service     monitor live queues
cancel                            skip / no-show / recall      read reports
view history                      view own statistics          publish announcements
```

A customer picks a service, receives a ticket such as `FIN-023`, and watches their position, the number
now being served and an estimated wait — all computed by the server from the database, refreshed by
polling. Staff call tickets to a counter and move them through
`waiting → called → serving → completed`. Admins watch the whole thing and pull reports.

---

## Design documents

| Document | Contents |
| --- | --- |
| [`docs/architecture.md`](docs/architecture.md) | System architecture, layer contract, request lifecycle, technology decisions, concurrency model, security model, folder structure |
| [`docs/database.md`](docs/database.md) | Mermaid ER diagram, relationship explanation, every table with columns/constraints/indexes, deletion policy, seed plan, Prisma appendix |
| [`docs/queue-engine.md`](docs/queue-engine.md) | Ticket state machine, concurrency-safe numbering, position and estimated-wait algorithms, all 14 business rules mapped to enforcement points |
| [`docs/api.md`](docs/api.md) | Complete `/api/v1` REST specification, response envelope, error codes, role matrix |
| [`docs/flutter-app.md`](docs/flutter-app.md) | Navigation map, 33 screens, Riverpod provider graph, reusable widgets, theme, network layer |
| [`docs/roadmap.md`](docs/roadmap.md) | Ten phases with objectives, files, database/API/Flutter changes and test procedures |

---

## Technology stack

| Layer | Choice |
| --- | --- |
| Client | Flutter (Material 3), Dart, Riverpod, GoRouter, Dio, flutter_secure_storage, fl_chart |
| API | Node.js 20+, Express 4, TypeScript, zod, jsonwebtoken, bcryptjs, helmet, express-rate-limit |
| Database | MySQL 8 (`smart_queue`), InnoDB, `mysql2` with parameterised statements and explicit transactions |
| Tests | Jest + Supertest (backend), `flutter_test` + mocktail (client) |

---

## Repository layout

```text
mobile/      Flutter application
server/      Express + TypeScript API
database/    SQL migrations, seed data, diagrams
docs/        architecture · database · api · queue-engine · flutter-app · roadmap
```

---

## Quick start

```bash
# 1. database
mysql -u root -p -e "CREATE DATABASE smart_queue CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# 2. api
cd server
cp .env.example .env          # set DATABASE_URL and JWT_SECRET
npm install
npm run db:migrate
npm run db:seed
npm run dev                   # http://localhost:5000/api/v1

# 3. client
cd ../mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:5000/api/v1
```

Android emulator: use `http://10.0.2.2:5000/api/v1`. Physical device: your machine's LAN IP.

The Flutter client lives in [`mobile/`](mobile/) and is documented in [`mobile/README.md`](mobile/README.md).
Platform folders are not committed, so the first run needs `flutter create .` — see that README.

### Running without a MySQL server

The repository layer talks to an interface, not to MySQL directly, so the whole API and its test suite
can run on file-backed SQLite with the identical schema. Change one line in `.env`:

```bash
DATABASE_URL=sqlite://../database/local/dev.db
npm run db:reset      # migrate + seed in one step
npm run dev
```

MySQL remains the deployment target; this is only so the project can be marked on a machine without a
database server.

### Tests

```bash
cd server
npm run typecheck     # tsc --noEmit
npm test              # 250 tests
```

| Suite | Tests | Covers |
| --- | --- | --- |
| `tests/schema.test.ts` | 20 | every table, unique key and index; database-level rejection of a duplicate active ticket |
| `tests/auth.test.ts` | 30 | registration, hashing, login, sessions, revocation, RBAC |
| `tests/services.test.ts` | 30 | catalogue, search, pagination, admin CRUD, hours, queue settings |
| `tests/queue.engine.test.ts` | 43 | joining, ticket numbering, estimated wait, position tracking, §85 end to end |
| `tests/transitions.test.ts` | 59 | the ticket state machine, every legal and illegal edge, who may drive it |
| `tests/concurrency.test.ts` | 14 | §60 — simultaneous joins, simultaneous calls, database-level guards |
| `tests/notifications.test.ts` | 20 | the inbox: ownership isolation, filters, paging, idempotent mark-read, announcement visibility |
| `tests/staff.test.ts` | 34 | the staff console: Rule 4 assignment scoping, Rule 5 counter conflicts, the on/off-duty switch, the dashboard, statistics attribution, handled-ticket history, §74 steps 7–13 |

---

## Demo accounts (seeded)

| Role | Email | Password |
| --- | --- | --- |
| Super admin | `super@smartqueue.test` | `Password123!` |
| Admin | `admin@smartqueue.test` | `Password123!` |
| Staff | `jane.staff@smartqueue.test` | `Password123!` |
| Customer | `john.doe@smartqueue.test` | `Password123!` |

---

## The part that matters

This is not a CRUD app with a queue table bolted on. The graded core is the **queue engine**:

* ticket numbers allocated under a `SELECT … FOR UPDATE` row lock so 25 simultaneous joins produce
  25 consecutive numbers and never a duplicate;
* a unique key on `(queue_id, sequence_number)` and a **generated column** that makes "one active ticket
  per user per service" a database guarantee rather than an application hope;
* positions and waiting-time estimates recomputed from live rows on every read — nothing cached, nothing
  hard-coded;
* an explicit state machine where every illegal transition is rejected with a 409 and every legal one is
  written inside a transaction together with its audit event and notification.

See [`docs/queue-engine.md`](docs/queue-engine.md).
