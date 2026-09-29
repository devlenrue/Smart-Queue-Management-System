# §85 walkthrough

The brief's success criteria (§85) say the system works when a customer can take a ticket, watch
their place, be called, be served and be counted — all of it through the real API and the real
database, with no faked data anywhere in the client.

This is that walkthrough, as an executable script rather than a claim.

```bash
cd server
npm run dev            # in one terminal
npm run walkthrough    # in another
```

It talks only to documented endpoints, it writes only what a real user could write, and the one
piece of configuration it changes — today's opening hours, so the script can be run after 5 p.m. —
it puts back on exit.

Set `BASE` to point it somewhere else (`BASE=http://192.168.1.5:5000/api/v1 npm run walkthrough`),
or `SERVICE_ID` to walk a different queue.

---

## What each step proves

| Step | Criterion |
| --- | --- |
| 0 | The API is up and can reach its database |
| 1 | Registration works, and self-registration is **always** a customer — the assertion fails the script otherwise |
| 2 | The catalogue carries **live** figures computed by the server: waiting, serving, now-serving, estimated wait |
| 3 | Joining issues a ticket **server-side** in the `FIN-014` format (§17), with position, people ahead and the estimate (§19) |
| 4 | **Rule 1** — one active ticket per user per service, refused with `DUPLICATE_ACTIVE_TICKET` |
| 5 | Position tracking is recomputed from live rows |
| 6 | **Rule 5** — a counter already serving somebody cannot be given a second ticket (`COUNTER_BUSY`) |
| 7 | `call-next` takes the longest-waiting ticket, in order, one at a time |
| 8 | The customer's own view reflects the clerk's action |
| 9 | The full transition chain `called → serving → completed` |
| 10 | The state machine refuses an illegal repeat with `INVALID_STATE_TRANSITION` (409), so nothing is double-counted |
| 11 | Ownership isolation — another customer reading the ticket gets `403` |
| 12 | Notifications were written at each step, in the same transaction as the change |
| 13 | The administrator's daily report already includes the visit |
| 14 | CSV export is produced by the **server**, with the right content type and filename |
| 15 | RBAC — a customer asking for a report gets `403` |

---

## A recorded run

Against the seeded database on the SQLite fallback, 29 September 2026. Every line below is the
script's own output, unedited.

```text
══ SmartQueue — §85 walkthrough against http://localhost:5000/api/v1 ══

── 0. the API is up and the database is reachable
   status ok · database up (sqlite) · timezone Africa/Nairobi

── 0b. the office may be shut — widen today's hours for the run
   today's hours were: {"dayOfWeek": 2, "dayName": "Tuesday", "openingTime": "08:00", "closingTime": "17:00", "status": "open"}
   Service hours updated → 00:00–23:59 for this run

── 1. a new customer registers
   Amina Walker · role customer · id 24

── 2. browses the service catalogue — live figures, server-computed
   ADM  Admissions         open     waiting 7   serving 1   now ADM-007  est 84 min
   FIN  Finance Office     open     waiting 6   serving 2   now FIN-006  est 18 min
   LIB  Library            open     waiting 7   serving 0   now —        est 28 min
   REG  Registrar          open     waiting 7   serving 1   now REG-007  est 63 min
   STA  Student Affairs    open     waiting 7   serving 1   now STA-006  est 49 min

── 3. joins a queue — the server issues the ticket number
   Ticket FIN-014 issued
   FIN-014 · waiting · position 7 · 6 ahead · est 18 min over 2 counters

── 4. Rule 1 — one active ticket per user per service
   refused DUPLICATE_ACTIVE_TICKET — You already have an active ticket (FIN-014) for Finance Office.

── 5. tracks position
   position 7 · 6 ahead · est 18 min · now serving FIN-006

── 6. a clerk signs in — Rule 5 stops a second ticket at a busy counter
   Finance Office at Finance Office Counter 1 · holding FIN-006 (serving) · 7 waiting
   refused COUNTER_BUSY — Finance Office Counter 1 is already serving ticket FIN-006. Complete or skip it first.
   cleared — Completed FIN-006

── 7. the clerk works down the queue to our ticket
   called FIN-008
   called FIN-009
   called FIN-010
   called FIN-011
   called FIN-012
   called FIN-013
   called FIN-014

── 8. the customer's screen has changed
   FIN-014 is now called

── 9. called → serving → completed
   Serving FIN-014 → serving
   Completed FIN-014 → completed

── 10. the state machine refuses to complete it twice
   refused INVALID_STATE_TRANSITION — Ticket FIN-014 has already been completed and can no longer be changed.

── 11. another customer cannot read this ticket
   refused FORBIDDEN — You can only view your own tickets.

── 12. the customer was notified at each step
   3 unread
   · Service completed              Your Finance Office service is complete. Thank you for usi
   · Ticket FIN-014 is being called Please proceed to Counter 1.
   · Ticket FIN-014 issued          You are number 7 in the Finance Office queue. Estimated wa

── 13. the administrator's daily report reflects it
   issued 66 · served 31 · cancelled 2 · skipped 0 · no-show 1
   average wait 127.1 min · average service 28.7 min

── 14. …and exports as the server's own CSV
   Content-Type: text/csv; charset=utf-8
   Content-Disposition: attachment; filename="smartqueue-daily-2026-09-29.csv"
   Date,Service,Code,Issued,Served,Cancelled,Skipped,No show,Average wait (min),Average service (min)
   2026-09-29,Admissions,ADM,14,6,0,0,0,16.3,13
   2026-09-29,Finance Office,FIN,14,11,1,0,1,325.4,64.4

── 15. a customer may not read a report
   refused FORBIDDEN — You do not have permission to perform this action.

══ walkthrough complete ══
   hours restored to 08:00–17:00
```

Two figures in step 13 deserve a word. The averages look enormous because the script completes
tickets the seed created hours earlier — their wait is measured from when they joined, which is
correct and is exactly why the number is large. Run it against a queue you filled yourself in the
last ten minutes and the averages come back to single digits.

---

## Doing it by hand

If you would rather click through it, [`docs/user-guide.md`](user-guide.md) is the same journey with
screens instead of `curl`: §1.3 takes the ticket, §2.2 calls and serves it, §3.8 finds it in the
report.
