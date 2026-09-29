# SmartQueue — REST API Specification

**Base URL** `http://<host>:5000/api/v1`
**Auth** `Authorization: Bearer <jwt>`
**Content type** `application/json`

---

## 1. Response envelope (§58)

Success:

```json
{ "success": true, "message": "Ticket created successfully", "data": { } }
```

Paginated success — `data` is the array, `meta` carries paging:

```json
{
  "success": true,
  "message": "Tickets retrieved",
  "data": [],
  "meta": { "page": 1, "limit": 20, "total": 137, "totalPages": 7 }
}
```

Error:

```json
{
  "success": false,
  "message": "Unable to join queue",
  "code": "QUEUE_FULL",
  "errors": [{ "field": "serviceId", "message": "The queue for this service is full" }]
}
```

`errors` is `[]` for non-field errors. `code` is a stable machine-readable string the Flutter client maps to
a friendly message; `message` is already user-safe. Raw exceptions are never returned (§63).

### Status codes

| Code | Used for |
| --- | --- |
| 200 | OK |
| 201 | Created (register, join queue, create service/counter/staff/announcement) |
| 204 | No content (hard delete) |
| 400 | Malformed request |
| 401 | Missing/invalid/expired/revoked token, bad credentials |
| 403 | Authenticated but not permitted (wrong role, not assigned to service) |
| 404 | Resource does not exist |
| 409 | Business-rule conflict (duplicate ticket, queue full, closed, bad state transition) |
| 413 | Request body over the 256 kB ceiling |
| 422 | Validation failed |
| 429 | Rate limited |
| 500 | Unexpected server error |

### Error code catalogue

Every code the API can return, and the one status it is always paired with. This is not prose kept in
step by hand: the list lives in `server/src/utils/AppError.ts` as `ERROR_CATALOGUE`, the middleware
reads the status from it, and `server/tests/errors.test.ts` walks it and fails the build if a 4xx code
has no negative-path test.

| Status | Codes | Meaning |
| --- | --- | --- |
| 400 | `BAD_REQUEST` | The request could not be read: unparseable JSON, or a clerk calling `call-next` with no counter to call it to |
| 401 | `UNAUTHENTICATED` · `INVALID_CREDENTIALS` · `TOKEN_EXPIRED` · `TOKEN_REVOKED` | No usable identity. `INVALID_CREDENTIALS` is deliberately identical for a wrong password and an unknown email — no account enumeration |
| 403 | `FORBIDDEN` · `ACCOUNT_INACTIVE` · `ACCOUNT_SUSPENDED` · `NOT_ASSIGNED_TO_SERVICE` | Identified, but not allowed. The last one is Rule 4 |
| 404 | `NOT_FOUND` · `NO_WAITING_TICKETS` | Nothing there. `NO_WAITING_TICKETS` answers `call-next` on an empty queue |
| 409 | `EMAIL_TAKEN` · `PHONE_TAKEN` · `SERVICE_CODE_TAKEN` · `COUNTER_NUMBER_TAKEN` · `STAFF_ALREADY_ASSIGNED` · `DUPLICATE_ACTIVE_TICKET` · `REJOIN_NOT_ALLOWED` · `SERVICE_CLOSED` · `SERVICE_INACTIVE` · `OUTSIDE_SERVICE_HOURS` · `QUEUE_PAUSED` · `QUEUE_CLOSED` · `QUEUE_FULL` · `INVALID_STATE_TRANSITION` · `CANCELLATION_NOT_ALLOWED` · `COUNTER_BUSY` · `COUNTER_OFFLINE` · `CONFLICT` | The request is well formed but fights the current state of the world. This is where the fourteen business rules of §59 land |
| 413 | `PAYLOAD_TOO_LARGE` | Over `express.json({ limit: '256kb' })`. Translated deliberately — an untranslated body-parser error would surface as a 500 |
| 422 | `VALIDATION_ERROR` | Zod rejected the body, query or params. The only code that routinely fills `errors[]` with `{ field, message }` |
| 429 | `RATE_LIMITED` | A limiter tripped. See §15 |
| 500 | `INTERNAL_ERROR` · `DATABASE_ERROR` | Our fault. The message is generic and the stack is logged, never sent (§63) |

---

## 2. Role matrix

`C` customer · `S` staff · `A` admin · `SA` super_admin · `—` public

| Area | Endpoint | C | S | A | SA |
| --- | --- | :-: | :-: | :-: | :-: |
| Auth | register / login | — | — | — | — |
| Auth | me / logout / change-password | ✓ | ✓ | ✓ | ✓ |
| Services | list, get | ✓ | ✓ | ✓ | ✓ |
| Services | create, update, delete, hours, settings | | | ✓ | ✓ |
| Queues | list, status | ✓ | ✓ | ✓ | ✓ |
| Queues | join | ✓ | | | |
| Queues | pause / resume / close | | | ✓ | ✓ |
| Queues | monitor | | ✓ | ✓ | ✓ |
| Tickets | my, get own, cancel, position | ✓ | | | |
| Tickets | next / call / recall / start / complete / skip / no-show | | ✓ | ✓ | ✓ |
| Counters | list | | ✓ | ✓ | ✓ |
| Counters | create / update / status | | | ✓ | ✓ |
| Staff | list / create / update / assign / unassign | | | ✓ | ✓ |
| Users | list / update status / delete | | | ✓ | ✓ |
| Users | change role, manage admins | | | | ✓ |
| Notifications | list / read / read-all | ✓ | ✓ | ✓ | ✓ |
| Announcements | list (published) | ✓ | ✓ | ✓ | ✓ |
| Announcements | create / update / publish / delete | | | ✓ | ✓ |
| Reports | daily / services / staff / queues | | | ✓ | ✓ |
| Dashboard | admin summary | | | ✓ | ✓ |
| Dashboard | staff summary | | ✓ | ✓ | ✓ |
| System | settings | | | | ✓ |

---

## 3. Auth — `/auth`

### `POST /auth/register` → 201 (public, rate limited)

```json
{
  "firstName": "John", "lastName": "Doe",
  "email": "john.doe@example.com", "phone": "+254712345678",
  "password": "Password123!", "confirmPassword": "Password123!"
}
```

Validation: all required · valid email (unique) · phone 7–20 chars, `+` and digits · password ≥ 8 with a
letter and a digit · `confirmPassword` must match. Registration always creates a `customer`; role can never
be set from this endpoint.

```json
{ "success": true, "message": "Registration successful",
  "data": { "token": "eyJ…", "user": { "id": 24, "firstName": "John", "lastName": "Doe",
            "email": "john.doe@example.com", "phone": "+254712345678",
            "role": "customer", "status": "active", "createdAt": "2026-09-29T08:12:03.000Z" } } }
```

Errors: `422 VALIDATION_ERROR` · `409 EMAIL_TAKEN` · `409 PHONE_TAKEN`.

### `POST /auth/login` → 200 (public, rate limited)

`{ "email": "...", "password": "..." }` → same `{ token, user }` payload.
Errors: `401 INVALID_CREDENTIALS` (identical message for unknown email and wrong password) ·
`403 ACCOUNT_SUSPENDED` · `403 ACCOUNT_INACTIVE`.

### `GET /auth/me` → 200 — current user + `activeTicketCount` + `unreadNotifications`.

### `POST /auth/logout` → 200 — writes the token `jti` to `revoked_tokens`.

### `POST /auth/change-password` → 200 — `{ currentPassword, newPassword, confirmPassword }`.

---

## 4. Services — `/services`

### `GET /services`

Query: `?status=open&category=Academic&search=fin&page=1&limit=20`

Each item is enriched with **live** queue figures (never client-computed):

```json
{ "success": true, "message": "Services retrieved", "data": [
  { "id": 1, "name": "Finance Office", "code": "FIN",
    "description": "Fee payments, statements and clearance",
    "category": "Administration", "averageServiceTime": 5, "dailyCapacity": 200,
    "status": "open",
    "queue": { "queueId": 11, "status": "waiting", "waitingCount": 12,
               "servingCount": 2, "completedToday": 18, "nowServing": "FIN-018",
               "estimatedWaitMinutes": 20, "activeCounters": 3,
               "isAcceptingTickets": true, "capacityRemaining": 165 },
    "hoursToday": { "opensAt": "08:00", "closesAt": "17:00", "isOpenNow": true } } ],
  "meta": { "page": 1, "limit": 20, "total": 5, "totalPages": 1 } }
```

### `GET /services/:id` — as above plus `counters[]`, `hours[]`, `settings`, `announcements[]`.

### `POST /services` → 201 · admin

```json
{ "name": "Finance Office", "code": "FIN", "description": "...", "category": "Administration",
  "averageServiceTime": 5, "dailyCapacity": 200, "status": "open" }
```

Creates the service **and** its default `queue_settings` row in one transaction.
Errors: `409 SERVICE_CODE_TAKEN`, `422 VALIDATION_ERROR`.

### `PUT /services/:id` · `DELETE /services/:id` (soft → `status='inactive'`; `?hard=true` is `super_admin` only)

### Hours and settings

```text
GET   /services/:id/hours          PUT /services/:id/hours      { "hours": [{ "dayOfWeek":1, "openingTime":"08:00", "closingTime":"17:00", "status":"open" }, …] }
GET   /services/:id/settings       PUT /services/:id/settings   { "maxQueueSize":100, "allowCancellation":true, "allowRejoin":true, "notificationThreshold":3, "estimatedServiceTime":5 }
```

---

## 5. Queues — `/queues`

### `GET /queues?date=2026-09-29&serviceId=1&status=waiting`

Today's queue per service with counts.

### `GET /queues/:id` — queue header + counters + first N waiting tickets (staff/admin see customer names).

### Joining — 201 · authenticated

Two addresses, one operation. Use whichever identifier you are holding:

```text
POST /services/:serviceId/queue/join     ← service card, deep link, QR code
POST /queues/:queueId/join               ← display board, staff tools
```

The request body is empty; sending `ticketNumber`, `sequenceNumber` or `status` has no effect, because
the ticket is generated entirely on the server (§17). Today's queue row is created on first use, so a
service that nobody has visited yet still works. Everything below is computed inside the transaction
described in `docs/queue-engine.md` §3.

```json
{ "success": true, "message": "Ticket FIN-023 issued",
  "data": { "ticket": { "id": 402, "ticketNumber": "FIN-023", "sequenceNumber": 23,
              "status": "waiting", "serviceId": 1, "serviceName": "Finance Office",
              "serviceCode": "FIN", "queueId": 11, "queueDate": "2026-09-29",
              "joinedAt": "2026-09-29T10:42:11.000Z", "calledAt": null,
              "counter": null, "estimatedWaitMinutes": 20, "waitedMinutes": 0 },
            "position": { "ticketId": 402, "ticketNumber": "FIN-023", "status": "waiting",
                          "position": 5, "peopleAhead": 4, "nowServing": "FIN-018",
                          "estimatedWaitMinutes": 20, "activeCounters": 2,
                          "queueStatus": "waiting", "counter": null,
                          "updatedAt": "2026-09-29T10:42:11.000Z" } } }
```

Failure modes (all 409 unless noted). Messages name the service, because "this queue is full" is
useless to someone with four tabs open:

| `code` | `message` |
| --- | --- |
| `SERVICE_INACTIVE` | `Finance Office is not currently available.` |
| `SERVICE_CLOSED` | `Finance Office is currently closed.` |
| `OUTSIDE_SERVICE_HOURS` | `Finance Office is currently closed. It opens at 8:00 AM.` |
| `QUEUE_PAUSED` | `The Finance Office queue is paused and is not accepting new tickets.` |
| `QUEUE_CLOSED` | `The Finance Office queue is closed for today.` |
| `QUEUE_FULL` | `The Finance Office queue has reached its capacity for today.` |
| `DUPLICATE_ACTIVE_TICKET` | `You already have an active ticket (FIN-019) for Finance Office.` |
| `REJOIN_NOT_ALLOWED` | `You have already been served by Finance Office today.` |
| 401 `UNAUTHENTICATED` | no bearer token |
| 404 `NOT_FOUND` | no such service or queue |
| 429 `RATE_LIMITED` | `joinLimiter` tripped |

### `GET /queues/:id/status` — the polling endpoint (cheap, 2–5 s)

`GET /queues/:id` and `GET /services/:id/queue` return the identical payload; the latter resolves
today's queue for you.

```json
{ "success": true, "message": "Queue status retrieved",
  "data": { "queueId": 11, "serviceId": 1, "serviceName": "Finance Office", "serviceCode": "FIN",
            "queueDate": "2026-09-29", "status": "waiting",
            "nowServing": "FIN-018", "currentNumber": 18,
            "waitingCount": 12, "servingCount": 2, "completedToday": 45,
            "cancelledToday": 3, "skippedToday": 2, "noShowToday": 1,
            "ticketsIssuedToday": 30, "activeCounters": 3,
            "averageWaitMinutes": 18, "averageServiceMinutes": 6,
            "estimatedWaitMinutes": 24, "isAcceptingTickets": true,
            "capacityRemaining": 70, "updatedAt": "2026-09-29T10:45:00.000Z" } }
```

### `POST` or `PATCH` `/queues/:id/pause` · `/resume` · `/close` · admin → the updated queue status.

`resume` returns the queue to `waiting`. Both verbs are accepted.

### `GET /queues/:id/monitor` · staff+admin (§35)

```json
{ "data": { "service": { "id":1, "name":"Finance Office", "code":"FIN" },
  "nowServing": "FIN-018",
  "counters": [ { "counterId":1, "counterNumber":1, "name":"Finance Counter 1",
                  "status":"busy", "staffName":"Jane Wanjiku", "currentTicket":"FIN-018" } ],
  "waiting": [ { "ticketNumber":"FIN-020", "sequenceNumber":20, "waitedMinutes":11 } ],
  "stats": { "waiting":5, "serving":2, "completed":45, "cancelled":3, "skipped":2,
             "noShow":1, "averageWaitMinutes":14 } } }
```

---

## 6. Tickets — `/tickets`

### Customer

| Endpoint | Notes |
| --- | --- |
| `GET /tickets/my?status=active` | `active` → `waiting,called,serving`; any single status also works; omit for all. Paginated history (§36). `GET /tickets` is the same list |
| `GET /tickets/active` | the live tickets only, unpaginated — what the customer dashboard opens with |
| `GET /tickets/:id` | owner, or any staff/admin |
| `GET /tickets/:id/position` | the poll target for the ticket screen; also what triggers the "your turn is approaching" notification |
| `GET /tickets/:id/events` | the audit timeline (owner or staff/admin) |
| `POST /tickets/:id/cancel` | owner (or an admin acting for them); requires `status='waiting'` and `allowCancellation` |

Cancel errors: `403 FORBIDDEN` (not owner) · `409 CANCELLATION_NOT_ALLOWED` ·
`409 INVALID_STATE_TRANSITION` (`Ticket FIN-023 is called and cannot be cancelled.`).

### Staff

All of these require `staff|admin|super_admin` **and** an active `staff_assignments` row for the service
(Rule 4) — otherwise `403 NOT_ASSIGNED_TO_SERVICE`. `admin` and `super_admin` supervise every service,
so the assignment check does not apply to them.

| Endpoint | Body | Effect |
| --- | --- | --- |
| `POST /tickets/next` | `{ "serviceId": 1, "counterId": 2 }` | atomically picks the lowest `waiting` sequence and calls it. `counterId` defaults to the caller's own counter. `404 NO_WAITING_TICKETS` when the queue is empty. `POST /tickets/call-next` is the same endpoint |
| `POST /tickets/:id/call` | `{ "counterId": 2 }` | call a specific waiting ticket |
| `POST /tickets/:id/recall` | — | re-notify; ticket must already be `called` |
| `POST /tickets/:id/start` | — | `called → serving` |
| `POST /tickets/:id/complete` | — | `serving → completed` |
| `POST /tickets/:id/skip` | `{ "reason": "optional" }` | `waiting\|called → skipped` |
| `POST /tickets/:id/no-show` | — | `called → no_show` |

Every one of them returns the updated ticket plus the refreshed queue snapshot so the staff UI needs a
single round trip:

```json
{ "success": true, "message": "Ticket FIN-023 called to Counter 2",
  "data": { "ticket": { "id":402, "ticketNumber":"FIN-023", "status":"called",
              "calledAt":"2026-09-29T10:56:02.000Z",
              "counter": { "id":2, "counterNumber":2, "name":"Finance Counter 2" },
              "customer": { "id":24, "firstName":"John", "lastName":"Doe", "phone":"+2547…" },
              "waitedMinutes": 14 },
            "queue": { "waitingCount": 11, "nowServing": "FIN-023", "completedToday": 45 } } }
```

Errors: `409 INVALID_STATE_TRANSITION`, `409 COUNTER_BUSY` (Rule 5), `409 COUNTER_OFFLINE`,
`404 NOT_FOUND`.

### `GET /tickets/:id/events` — the audit timeline for a ticket (owner or staff/admin).

```json
{ "data": [ { "id": 901, "eventType": "joined",  "actorName": "John Doe",
              "description": "Joined the Finance Office queue", "createdAt": "…" },
            { "id": 902, "eventType": "called",  "actorName": "Jane Wanjiku",
              "description": "Called to Finance Counter 2", "createdAt": "…" } ] }
```

The internal `threshold_notified` marker used to de-duplicate the "approaching" alert is filtered out.

---

## 7. Counters — `/counters`

```text
GET    /counters?serviceId=1&status=available      staff+                        ✅ Phase 6
PATCH  /counters/:id/status { status: "available" | "busy" | "offline" }         ✅ Phase 6
                                                   staff (own counter) / admin
POST   /counters            { serviceId, counterNumber, name, staffId? }  admin → 201  ✅ Phase 7
PUT    /counters/:id        { counterNumber, name, status }              admin         ✅ Phase 7
DELETE /counters/:id                                                     admin → 204   ✅ Phase 7
POST   /counters/:id/assign { staffId }  /  DELETE /counters/:id/assign  admin         ✅ Phase 7
```

`409 COUNTER_NUMBER_TAKEN`, `409 STAFF_ALREADY_ASSIGNED`, `409 COUNTER_BUSY` (cannot take a counter
offline, reassign it or delete it while it is serving).

Creating a counter with `staffId` posts that clerk to it in the same transaction, so a counter is
never left half-created if the clerk turns out to be assigned elsewhere. `POST /counters/:id/assign`
ends any assignment the clerk already had; `DELETE /counters/:id/assign` frees the counter and closes
the `staff_assignments` row.

`GET /counters` returns the `toCounterDto` shape — `{ id, serviceId, serviceName, serviceCode,
counterNumber, name, status, staff, currentTicket }`. A staff member asking for a `serviceId` that is
not their own gets `403 NOT_ASSIGNED_TO_SERVICE`; admins may ask for any.

`PATCH /counters/:id/status` answers with `{ id, serviceId, counterNumber, name, status,
assignedStaffId }`.

---

## 8. Staff — `/staff`

```text
GET  /staff/:id/statistics?from=&to=                             staff(self)+admin   ✅ Phase 6
GET  /staff/:id/tickets?from=&to=&status=&page=&limit=           staff(self)+admin   ✅ Phase 6
GET  /staff?serviceId=1&status=active&search=jane&unassigned=true          admin    ✅ Phase 7
POST /staff  { firstName,lastName,email,phone,password,serviceId?,counterId? } admin → 201 ✅ Phase 7
PUT  /staff/:id  { firstName,lastName,phone,status }                       admin    ✅ Phase 7
POST /staff/:id/assign    { serviceId, counterId? }                        admin    ✅ Phase 7
POST /staff/:id/unassign  { assignmentId? }                                admin    ✅ Phase 7
```

A roster row is the user plus where they are working, or `null` when they have not been posted:

```json
{ "id": 4, "firstName": "Jane", "fullName": "Jane Wanjiku", "role": "staff", "status": "active",
  "posting": { "assignmentId": 4, "serviceId": 1, "serviceName": "Finance Office",
               "serviceCode": "FIN", "counterId": 2, "counterNumber": 2,
               "counterName": "Finance Counter 2", "counterStatus": "available",
               "assignedAt": "2026-09-01T05:00:00.000Z" } }
```

`unassigned=true` filters to clerks with no posting — the list an administrator works from when a
counter needs covering. Suspending a clerk through `PUT /staff/:id` frees their counter and ends the
assignment in the same transaction, so a suspended account can never hold a desk.

`:id` accepts the literal `me`, so the client never has to interpolate its own user id into a URL it
is already authenticated for. A staff member reading somebody else's figures gets `403`.

`GET /staff/:id/statistics` (§37):

```json
{ "data": { "staff": { "id":7, "name":"Jane Wanjiku",
                       "email":"jane.staff@smartqueue.test", "role":"staff" },
  "range": { "from":"2026-09-23", "to":"2026-09-29" },
  "ticketsServed": 312, "ticketsSkipped": 11, "ticketsNoShow": 6, "ticketsRecalled": 9,
  "ticketsHandled": 329, "completionRate": 95,
  "averageServiceMinutes": 5.8, "averageWaitMinutes": 17.2,
  "byDay": [ { "date":"2026-09-28", "served":42, "averageServiceMinutes":5.5 } ] } }
```

The range defaults to the last seven days. `completionRate` is `ticketsServed ÷ ticketsHandled`, as a
percentage — a counter that skips half its queue shows it here.

**Attribution.** A ticket counts towards a staff member when *they* caused the event
(`queue_events.user_id`), not when it happens to sit at their counter. Counters get reassigned; the
audit trail does not move.

### `GET /staff/:id/tickets` — the counter's own history

Added in Phase 6. `GET /tickets/my` is scoped to the caller's tickets **as a customer**, so it cannot
answer "what did I handle today?". This one lists the tickets the staff member called, recalled,
started, completed, skipped or marked as a no-show — each ticket once, however many times they
touched it.

```json
{ "data": { "tickets": [ { "id":402, "ticketNumber":"FIN-022", "status":"completed",
                           "customer": { "fullName":"Mary Atieno", "phone":"…" },
                           "waitedMinutes":14, "serviceMinutes":6 } ],
            "range": { "from":"2026-09-23", "to":"2026-09-29" } },
  "meta": { "page":1, "limit":20, "total":48, "totalPages":3 } }
```

---

## 9. Users — `/users` (admin)

```text
GET    /users?role=customer&status=active&search=doe&page=1&limit=20
GET    /users/:id                  (profile + ticket counts + last activity)
PATCH  /users/:id/status           { status }
PATCH  /users/:id/role             { role }            super_admin only
DELETE /users/:id                  super_admin only → 204
```

`GET /users/:id` is the profile plus what the account has actually done:

```json
{ "data": { "id": 9, "fullName": "John Doe", "role": "customer", "status": "active",
  "activity": { "totalTickets": 15, "completed": 11, "cancelled": 2, "noShow": 0,
                "active": 2, "lastActivityAt": "2026-09-29T06:01:18.000Z" },
  "posting": null } }
```

Nobody may administer their own account through these routes (`403`), an admin may not touch another
admin, and only a super admin may change a role or delete. Suspending or demoting a clerk frees their
counter. Deleting is refused with `409 CONFLICT` while the account still holds an active ticket.

Own profile for every role:

```text
GET  /profile        PUT /profile   { firstName, lastName, phone }
```

---

## 10. Notifications — `/notifications`

```text
GET   /notifications?isRead=false&type=queue&page=1&limit=20
GET   /notifications/unread-count        → { "count": 3 }
PATCH /notifications/:id/read
PATCH /notifications/read-all
```

---

## 11. Announcements — `/announcements`

```text
GET    /announcements?serviceId=1                 any role — published & unexpired only
GET    /announcements/:id                         any role — published only
GET    /announcements/manage?status=draft&serviceId=&search=&page=&limit=   admin
GET    /announcements/manage/:id                                            admin
POST   /announcements  { title, content, serviceId?, expiresAt?, status }   admin → 201
PUT    /announcements/:id   { title, content, serviceId, clearService, expiresAt }
PATCH  /announcements/:id/publish   ·   PATCH /announcements/:id/archive
DELETE /announcements/:id                                                   admin → 204
```

The public list never shows a draft, so the composer reads `/announcements/manage`, which carries the
extra `status` field. Publishing fans a notification out to every active customer — service notices go
only to that service's customers — and it happens **once**, on the transition *into* `published`;
re-publishing an already-published notice is a no-op rather than a second round of notifications.

---

## 12. Dashboards

### `GET /dashboard/admin` (§31)

```json
{ "data": { "today": "2026-09-29",
  "activeServices": 5, "activeQueues": 5, "activeCounters": 8, "staffOnDuty": 5,
  "customersWaiting": 32, "customersServedToday": 147,
  "averageWaitMinutes": 14, "averageServiceMinutes": 6,
  "ticketsIssuedToday": 186, "cancelledToday": 7, "skippedToday": 5, "noShowToday": 4,
  "byService": [ { "serviceId":1, "name":"Finance Office", "code":"FIN",
                   "waiting":12, "serving":2, "completed":45,
                   "averageWaitMinutes":18, "status":"open" } ],
  "servedPerDay": [ { "date":"2026-09-23", "label":"Monday", "served":80 } ],
  "statusBreakdown": { "waiting":32, "serving":8, "completed":147, "cancelled":7,
                       "skipped":5, "noShow":4 } } }
```

`servedPerDay` and `statusBreakdown` feed the charts of §42 — all values are SQL aggregates, none are
hard-coded. ✅ Phase 7. `?days=7` sizes the chart window (1–31) and `?date=` reports a different day;
the series is dense — quiet days come back as zeroes rather than gaps — and always ends on the day
being reported.

### `GET /dashboard/staff?serviceId=&counterId=` (§20) — ✅ Phase 6

The whole console in one request, so the waiting count in the header can never disagree with the list
under it. `currentTicket` and `upNext[]` are full ticket DTOs with the customer attached — the same
shape the transitions return — rather than the trimmed pair sketched during design.

```json
{ "data": {
  "today": "2026-09-29",
  "assigned": true,
  "assignment": { "id":4, "serviceId":1, "serviceName":"Finance Office", "serviceCode":"FIN",
                  "counterId":2, "counterNumber":2, "counterName":"Finance Counter 2",
                  "assignedAt":"…", "status":"active" },
  "service": { "id":1, "name":"Finance Office", "code":"FIN", "status":"open" },
  "counter": { "id":2, "serviceId":1, "counterNumber":2, "name":"Finance Counter 2",
               "status":"busy", "assignedStaffId":7 },
  "queue":   { "queueId":101, "waitingCount":12, "nowServing":"FIN-022", "completedToday":45, … },
  "currentTicket": { "id":402, "ticketNumber":"FIN-022", "status":"serving",
                     "customer": { "id":24, "fullName":"Mary Atieno", "phone":"…" },
                     "joinedAt":"…", "waitedMinutes":14, "serviceMinutes":3 },
  "upNext": [ { "id":403, "ticketNumber":"FIN-023", "waitedMinutes":11, "customer": { … } } ],
  "stats": { "waiting":12, "servedToday":9, "skippedToday":2, "noShowToday":1, "cancelledToday":0,
             "averageServiceMinutes":6, "averageWaitMinutes":18 } } }
```

`stats.servedToday` is what **this** clerk completed; the service-wide figure is
`queue.completedToday`.

An unassigned staff member gets `200` with `assigned:false` and everything else null or zero — the
screen then explains that an administrator needs to post them to a service, which is more useful than
a 403. Admins have no assignment either, so for them `serviceId` selects the desk to supervise and
defaults to the first open service.

---

## 13. Reports — `/reports` (admin) ✅ Phase 8

Four reports, one query contract. Every endpoint accepts

```text
?from=YYYY-MM-DD&to=YYYY-MM-DD&serviceId=<id>&staffId=<id>&format=json|csv
```

and answers `{ range, rows, totals }`. Omitting the range means **today**; giving only `from` means
that one day. Dates must exist on the calendar (`2026-13-40` is `422`) and a range may cover at most
**366 days**. `staffId` is only read by `/reports/staff`. Every route is `admin` or `super_admin` —
a clerk's own figures live at `/staff/me/statistics` (§8).

| Endpoint | Row |
| --- | --- |
| `GET /reports/daily` | date, serviceId, serviceName, serviceCode, issued, served, cancelled, skipped, noShow, averageWaitMinutes, averageServiceMinutes |
| `GET /reports/services` | serviceId, serviceName, serviceCode, status, issued, customersServed, cancelled, skipped, noShow, completionRate, averageWaitMinutes, averageServiceMinutes, peakHour, peakHourLabel, peakQueueLength |
| `GET /reports/staff` | staffId, staffName, email, serviceId, serviceName, serviceCode, ticketsHandled, ticketsServed, ticketsSkipped, ticketsNoShow, ticketsRecalled, averageServiceMinutes |
| `GET /reports/queues` | queueId, date, serviceId, serviceName, serviceCode, status, issued, served, openedAt, closedAt, peakQueue, averageQueue, countersUsed, utilisationPercent |

```json
{ "success": true, "message": "Daily report generated",
  "data": { "range": { "from": "2026-09-29", "to": "2026-09-29" },
    "rows": [ { "date": "2026-09-29", "serviceId": 1, "serviceName": "Finance Office",
                "serviceCode": "FIN", "issued": 13, "served": 3, "cancelled": 1,
                "skipped": 0, "noShow": 1,
                "averageWaitMinutes": 18.5, "averageServiceMinutes": 7.7 } ],
    "totals": { "issued": 215, "served": 150, "cancelled": 11, "skipped": 8, "noShow": 7,
                "averageWaitMinutes": 17, "averageServiceMinutes": 8.3 } } }
```

`totals` differs per report: the daily and service reports share the five counts plus both averages;
`/reports/staff` totals `{ staff, ticketsHandled, ticketsServed, ticketsSkipped, ticketsNoShow,
averageServiceMinutes }` (weighted by tickets served, not an average of averages); `/reports/queues`
totals `{ queues, issued, served, peakQueue, averageUtilisationPercent }`.

**Null is not zero.** `averageWaitMinutes` is `null` when no ticket in that group ever reached a
counter. Averages are rounded to one decimal place.

### 13.1 How the derived figures are defined

Counts and averages are plain SQL. Four columns are not, and are computed in `report.service.ts`:

| Figure | Definition |
| --- | --- |
| `averageWaitMinutes` | mean of `called_at − joined_at` over tickets that were called |
| `averageServiceMinutes` | mean of `completed_at − service_started_at` over completed tickets |
| `peakHour` | hour of day (0–23) in which the most tickets were **issued**; `peakHourLabel` is `"09:00–10:00"` |
| `peakQueue` / `peakQueueLength` | the largest number of people waiting **at the same instant** — a sweep over each ticket's `[joined_at, called_at)` interval. A wait that ends exactly when another begins is not counted twice |
| `averageQueue` | total waiting minutes ÷ minutes the queue was open — the mean number of people in the line while it ran |
| `utilisationPercent` | serving minutes ÷ (counters used × minutes open) × 100, capped at 100 |
| `openedAt` / `closedAt` | first ticket issued (or the queue row's creation) and the last activity recorded. A queue that is still open today reports `closedAt: null`, and its window is measured **to now** — an office open since eight and idle since ten is not 100% utilised |

A ticket still waiting when the report runs counts as waiting until now, or until the end of its own
day for a past date, so a queue left open on Monday cannot go on inflating Friday's figures.

### 13.2 CSV export

`?format=csv` returns the same rows as a file:

```text
HTTP/1.1 200 OK
Content-Type: text/csv; charset=utf-8
Content-Disposition: attachment; filename="smartqueue-daily-2026-09-29.csv"

Date,Service,Code,Issued,Served,Cancelled,Skipped,No show,Average wait (min),Average service (min)
2026-09-29,Finance Office,FIN,4,2,1,1,0,20,10
```

This is the **only** response in the API that is not the envelope of §1 — a spreadsheet cannot open
one. RFC 4180: CRLF line endings, fields quoted only when they contain a comma, quote, newline or
edge whitespace, embedded quotes doubled, and an empty cell where a value is `null`. The filename
carries the range (`smartqueue-services-2026-09-01_2026-09-30.csv` for a multi-day report).

---

## 14. System — `/system` (super_admin)

```text
GET   /system/settings          PUT /system/settings   { key: value, … }
GET   /system/health            → public: { status:"ok", uptime, database:"up", time }
```

A settings row is `{ key, value, description, updatedAt }`. Values are stored as text — `250` comes
back as `"250"` and `false` as `"false"` — because the table is deliberately schemaless; the client
interprets a value only where it needs to. Sending `null` for a key **deletes** it. Both routes are
`super_admin` only; an ordinary admin gets `403`.

---

## 15. Conventions

* **Naming** — JSON is `camelCase`, the database is `snake_case`; mapping happens in the repository layer.
* **IDs** — numbers in JSON.
* **Dates** — ISO-8601 UTC strings (`2026-09-29T10:42:11.000Z`); `queue_date` is a plain `YYYY-MM-DD`;
  `TIME` fields are `HH:mm`.
* **Paging** — `?page` (1-based, default 1) and `?limit` (default 20, max 100).
* **Sorting** — `?sort=field&order=asc|desc`; the field is checked against a per-endpoint allow-list before
  it ever reaches SQL.
* **Search** — `?search=` does a `LIKE` over a documented set of columns per endpoint (§40).
* **Idempotency** — every state-transition endpoint is safe to retry: a second `complete` on an already
  completed ticket returns `409 INVALID_STATE_TRANSITION`, never a double count.

### Transport hardening

Configured in `server/src/app.ts` and proved in `server/tests/security.test.ts`.

| Control | Setting | Notes |
| --- | --- | --- |
| Security headers | `helmet()` | `X-Content-Type-Options: nosniff`, `X-Frame-Options`, HSTS, `X-DNS-Prefetch-Control`. `X-Powered-By` is removed |
| CORS | `CORS_ORIGIN` (comma-separated, `*` in development) | An origin that is not on the list simply gets no `Access-Control-Allow-Origin` back |
| Body size | `256kb` on JSON and urlencoded | Over it → `413 PAYLOAD_TOO_LARGE` |
| Auth limiter | `RATE_LIMIT_AUTH_MAX`, default 30 per 15 min per IP | `/auth/register`, `/auth/login` — brute-force protection |
| Join limiter | `RATE_LIMIT_JOIN_MAX`, default 20 per 15 min per IP | `/services/:id/queue/join` — stops a stuck client hammering the queue |
| API limiter | `RATE_LIMIT_API_MAX`, default 1000 per 15 min per IP | Backstop over everything under `/api/v1`. A customer app polling flat out uses ~300 of it, so the limiter only ever catches abuse |

All three limiters answer with the normal envelope and `RateLimit-*` standard headers, so a client can
back off before it is cut off. They are skipped under `NODE_ENV=test` unless `RATE_LIMIT_IN_TESTS=true`,
which is how the security suite exercises them without making every other suite flaky.
