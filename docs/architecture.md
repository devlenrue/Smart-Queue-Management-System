# SmartQueue — System Architecture

> Design document · Phase 0 (design freeze) · Smart Queue Management System

---

## 1. One-paragraph summary

SmartQueue is a three-tier system. A **Flutter** client (Android / tablet / desktop / web) talks over
**HTTPS REST** to a **Node.js + Express + TypeScript** API, which owns *all* business logic and talks to a
**MySQL 8** database over a pooled, parameterised connection. The client never computes queue state: ticket
numbers, positions, waiting-time estimates and state transitions are produced by the server inside database
transactions. The client is a *view* over server state, refreshed by short polling.

---

## 2. Physical / logical architecture

```text
                    ┌─────────────────────────────────────────────┐
                    │              FLUTTER CLIENT                  │
                    │  (Android · Tablet · Desktop · Web)          │
                    │                                              │
                    │  features/auth      features/staff           │
                    │  features/customer  features/admin           │
                    │                                              │
                    │  Riverpod (state)  ·  GoRouter (navigation)  │
                    │  Dio ApiClient     ·  SecureStorage (JWT)    │
                    └───────────────────────┬──────────────────────┘
                                            │
                                            │  REST  /api/v1
                                            │  JSON  ·  Bearer JWT
                                            ▼
        ┌────────────────────────────────────────────────────────────────┐
        │                  NODE.JS + EXPRESS + TYPESCRIPT                │
        │                                                                │
        │  routes/        → URL surface, versioned under /api/v1         │
        │  middleware/    → auth, rbac, validate, rateLimit, errors      │
        │  validators/    → zod schemas (request contracts)              │
        │  controllers/   → HTTP in/out only, zero business logic        │
        │  services/      → THE QUEUE ENGINE + all business rules        │
        │  repositories/  → parameterised SQL, one table family each     │
        │  db/            → pool, transactions, migration runner         │
        └───────────────────────────────┬────────────────────────────────┘
                                        │
                                        │  mysql2/promise · prepared statements
                                        │  START TRANSACTION … SELECT … FOR UPDATE
                                        ▼
        ┌────────────────────────────────────────────────────────────────┐
        │                          MySQL 8  ·  smart_queue               │
        │                                                                │
        │  users · services · service_counters · service_hours           │
        │  queue_settings · queues · queue_tickets · queue_events        │
        │  staff_assignments · notifications · announcements             │
        │  revoked_tokens · system_settings                              │
        └────────────────────────────────────────────────────────────────┘
```

```mermaid
flowchart TD
    subgraph Client["Flutter client"]
        C1[Customer app]
        C2[Staff console]
        C3[Admin console]
    end

    subgraph API["Node.js / Express / TypeScript"]
        R[Routes /api/v1]
        MW[Middleware<br/>auth · rbac · validate · errors]
        CT[Controllers]
        SV[Services<br/>QUEUE ENGINE]
        RP[Repositories<br/>parameterised SQL]
    end

    DB[(MySQL 8<br/>smart_queue)]
    DISP[Public display board<br/>static page served by API]

    C1 & C2 & C3 -->|JSON + Bearer JWT| R
    R --> MW --> CT --> SV --> RP --> DB
    DISP -->|read-only polling| R
```

---

## 3. Layer contract (what is allowed where)

| Layer | May do | May **not** do |
| --- | --- | --- |
| `routes/` | Map URL → middleware chain → controller | Contain logic |
| `middleware/` | Authn, authz, validation, rate limit, error shaping | Query the DB for business data (except `auth` loading the user) |
| `validators/` | Declare zod request schemas | Touch the DB |
| `controllers/` | Read `req`, call one service, write the envelope | Business rules, SQL |
| `services/` | Business rules, transactions, orchestration | Know about `req`/`res`, raw driver types |
| `repositories/` | Parameterised SQL, row → domain mapping | Business rules, HTTP concerns |
| `db/` | Pool, `withTransaction`, migrations, dialect quirks | Domain knowledge |

**Rule of thumb:** if a rule from §59 of the brief (Rules 1–14) is being enforced, it lives in `services/`.
If a `?` placeholder is being bound, it lives in `repositories/`.

---

## 4. Request lifecycle (worked example: `POST /api/v1/queues/:id/join`)

```text
1. CORS + helmet + json body parser
2. rateLimit(join)                     → 429 if abused
3. requireAuth                         → verifies JWT, loads user, checks status=active, checks denylist
4. requireRole('customer')             → 403 otherwise
5. validate(joinQueueSchema)           → 422 with field errors otherwise
6. QueueController.join                → extracts userId + serviceId, calls the engine
7. QueueService.joinQueue()            ─┐
       withTransaction(async tx => {    │  ← ONE database transaction
         lock queue row FOR UPDATE      │
         re-check: service open?        │  Rule 2
         re-check: within hours?        │  §30
         re-check: queue status waiting?│  §29
         re-check: capacity left?       │  Rule 3
         re-check: no active ticket?    │  Rule 1
         allocate sequence_number       │  §60 concurrency
         format ticket_number FIN-023   │  §17
         insert queue_tickets           │
         insert queue_events(joined)    │
         insert notifications           │
       })                              ─┘
8. Estimated wait computed from live DB numbers (§19)
9. 201 { success:true, message, data:{ ticket, position } }
10. errorHandler turns any thrown AppError into the standard error envelope
```

Every step that writes more than one row is inside `withTransaction` (Rule 14).

---

## 5. Technology decisions and why

| Decision | Choice | Rationale |
| --- | --- | --- |
| API language | TypeScript | Compile-time contracts between layers; the brief prefers it |
| Web framework | Express 4 | Smallest concept count for a class project; middleware model maps 1:1 to the layer contract |
| DB access | `mysql2/promise` + hand-written SQL in repositories | The core of this project is a **queue engine** that needs `SELECT … FOR UPDATE` row locking, explicit transaction boundaries and real DDL (FKs, generated columns, composite unique keys). Hand-written parameterised SQL shows that work instead of hiding it behind an ORM. All SQL is parameterised → SQL-injection safe (§62). |
| Migrations | Plain, numbered `.sql` files + a tiny Node runner | The student can read exactly what the database looks like; `schema_migrations` table makes runs idempotent |
| Validation | `zod` | One schema = runtime validation + TS type |
| Auth | `jsonwebtoken` + `bcryptjs` | Exactly what the brief asks for |
| Realtime | HTTP polling (2–5 s) on the ticket / staff / monitor screens | §61 Option A. Simple, debuggable, no socket lifecycle to explain in a viva |
| Client state | Riverpod (`AsyncNotifier`, `StreamProvider` for polling) | Business logic stays out of widgets (§69) |
| Client routing | GoRouter with a role-aware redirect guard | Declarative deep links + one place for route protection |
| Client HTTP | Dio + interceptors (auth header, 401 handling, error mapping) | Centralised network layer (§70) |

### 5.1 Why not Prisma?

The brief allows Prisma ("*If using Prisma…*") but does not require it. Two reasons we do not:

1. **Locking.** Safe ticket numbering under concurrency (§60) needs `SELECT … FOR UPDATE`. In Prisma that is
   `$queryRaw` anyway, so the interesting code would be raw SQL sitting inside an ORM.
2. **Visibility.** A database-design module is being graded. Numbered SQL migrations with explicit
   `FOREIGN KEY … ON DELETE`, composite `UNIQUE` keys, generated columns and indexes are the artefact worth
   showing.

A Prisma equivalent of the schema is still provided in `docs/database.md` §9 for reference/comparison.

---

## 6. Concurrency model

Three places can race. Each has a defined strategy:

| Race | Strategy |
| --- | --- |
| Two customers join the same service at the same millisecond | `SELECT … FOR UPDATE` on the `queues` row serialises sequence allocation; `UNIQUE(queue_id, sequence_number)` and `UNIQUE(queue_id, ticket_number)` are the database-level safety net; a bounded retry handles the (theoretical) duplicate-key case |
| Two staff press **Call Next** at the same time | The transaction locks the *queue* row, then selects the next `waiting` ticket `ORDER BY sequence_number LIMIT 1 FOR UPDATE`; the loser sees the next ticket, never the same one |
| Two requests create today's queue row for the same service | `UNIQUE(service_id, queue_date)`; the loser catches `ER_DUP_ENTRY` and re-reads the winner's row |

Isolation level: MySQL default `REPEATABLE READ`. All queue mutations go through
`withTransaction()` which guarantees `COMMIT`/`ROLLBACK` and releases the connection.

---

## 7. Security model

| Control | Implementation |
| --- | --- |
| Password storage | `bcryptjs`, cost 10, `password_hash` never selected into any API response |
| Tokens | JWT HS256, `sub`/`role`/`jti`, `JWT_EXPIRES_IN` (default `7d`) |
| Logout | `jti` written to `revoked_tokens`; `requireAuth` rejects revoked tokens; expired rows pruned |
| Transport of token on client | `flutter_secure_storage` (Keystore/Keychain), never `SharedPreferences` |
| Authorization | `requireRole(...)` middleware + resource-level ownership checks in services (e.g. a customer may only cancel *their own* ticket; staff may only call tickets for a service they are assigned to — Rule 4) |
| Injection | 100 % parameterised statements; no string-concatenated SQL anywhere; identifiers (sort columns) validated against allow-lists |
| Transport | CORS allow-list from `CORS_ORIGIN`, `helmet`, JSON body size cap |
| Abuse | `express-rate-limit` on `/auth/*` and on join-queue |
| Secrets | `.env` only, `.env.example` committed, `.env` git-ignored; `JWT_SECRET` / `DATABASE_URL` never leave the server |
| Output hygiene | A serializer layer decides what leaves the API; internal error text is logged, not returned (§63) |

---

## 8. Error model

One `AppError` class carrying `statusCode`, `code`, `message` (user-safe) and optional `errors[]`.
Everything else that reaches the error middleware becomes a generic 500 with the detail written to the log
only.

| HTTP | `code` examples |
| --- | --- |
| 400 | `BAD_REQUEST`, `INVALID_STATE_TRANSITION` |
| 401 | `UNAUTHENTICATED`, `TOKEN_EXPIRED`, `INVALID_CREDENTIALS` |
| 403 | `FORBIDDEN`, `NOT_ASSIGNED_TO_SERVICE` |
| 404 | `NOT_FOUND` |
| 409 | `DUPLICATE_ACTIVE_TICKET`, `QUEUE_FULL`, `SERVICE_CLOSED`, `OUTSIDE_SERVICE_HOURS`, `COUNTER_BUSY`, `EMAIL_TAKEN` |
| 422 | `VALIDATION_ERROR` (with `errors: [{field, message}]`) |
| 429 | `RATE_LIMITED` |
| 500 | `INTERNAL_ERROR` |

---

## 9. Project folder structure

```text
Smart-Queue-Management-System/
│
├── mobile/                          # Flutter application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── constants/           # api paths, app strings, enums
│   │   │   ├── theme/               # Material 3 light + dark
│   │   │   ├── routing/             # GoRouter + role guard
│   │   │   ├── network/             # Dio client, interceptors, failure mapping
│   │   │   ├── storage/             # secure token storage
│   │   │   ├── errors/              # Failure types, user-facing messages
│   │   │   └── utils/               # formatters, validators, date helpers
│   │   ├── models/                  # immutable DTOs + fromJson/toJson
│   │   ├── services/                # one class per API group
│   │   ├── repositories/            # combine services + caching/polling
│   │   ├── providers/               # Riverpod providers
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── customer/{dashboard,services,queue,history,notifications,profile}
│   │   │   ├── staff/{dashboard,queue,statistics}
│   │   │   └── admin/{dashboard,services,counters,staff,users,queues,reports,announcements}
│   │   └── widgets/                 # AppButton, TicketCard, StatusBadge, …
│   ├── test/                        # widget + unit tests
│   └── pubspec.yaml
│
├── server/                          # Express API
│   ├── src/
│   │   ├── config/                  # env loading + typed config
│   │   ├── db/                      # pool, transactions, migrate, seed
│   │   ├── middleware/
│   │   ├── routes/
│   │   ├── controllers/
│   │   ├── services/                # queue engine lives here
│   │   ├── repositories/
│   │   ├── validators/
│   │   ├── utils/
│   │   ├── types/
│   │   ├── app.ts
│   │   └── server.ts
│   ├── public/                      # API docs page + public display board
│   ├── tests/                       # unit + integration (supertest)
│   ├── .env.example
│   ├── package.json
│   └── tsconfig.json
│
├── database/
│   ├── migrations/                  # 001_…sql … numbered, forward-only
│   ├── seed/                        # seed dataset
│   └── diagrams/                    # er-diagram.mmd, state machine
│
├── docs/
│   ├── architecture.md              ← this file
│   ├── database.md
│   ├── api.md
│   ├── queue-engine.md
│   ├── flutter-app.md
│   ├── roadmap.md
│   └── user-guide.md
│
├── README.md
└── .gitignore
```

---

## 10. Environments and configuration

`server/.env`:

```text
PORT=5000
NODE_ENV=development
DATABASE_URL=mysql://root:password@localhost:3306/smart_queue
JWT_SECRET=change-me
JWT_EXPIRES_IN=7d
CORS_ORIGIN=http://localhost:3000,http://localhost:8080
TZ=Africa/Nairobi
QUEUE_DEFAULT_SERVICE_MINUTES=5
QUEUE_NOTIFY_THRESHOLD=3
```

Flutter reads its base URL from a compile-time define, never a hard-coded IP (§71):

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5000/api/v1
```

Timezone: the server sets `TZ` once and does *all* date arithmetic (queue_date, service hours) in server
local time. The client only formats what the server sends (§30).

---

## 11. Deployment shape (class-project scale)

```text
one machine
 ├── mysqld            :3306
 ├── node dist/server.js  :5000     (pm2 or plain node)
 └── flutter build apk / flutter build web
```

No containers, no microservices, no message broker, no cache tier — deliberately (§82).
