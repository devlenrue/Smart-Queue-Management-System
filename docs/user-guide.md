# SmartQueue — user guide

One walkthrough per role, written against the running app rather than the design. Every screen name,
button label and message quoted here is the one on screen.

The system has four roles. Each signs in through the same door and lands somewhere different:

| Role | Lands on | Can do |
| --- | --- | --- |
| Customer | `/home` — Home tab | Browse services, take a ticket, watch the queue, cancel |
| Staff | `/staff/console` — Console tab | Work one counter: call, serve, complete, skip, no-show |
| Admin | `/admin/dashboard` | Run the institution: services, counters, staff, users, notices, reports |
| Super admin | `/admin/dashboard` | Everything an admin can do, plus system settings and role changes |

Seeded demo accounts — all share the password `Password123!`:

| Role | Email |
| --- | --- |
| Customer | `john.doe@smartqueue.test` |
| Staff | `jane.staff@smartqueue.test` |
| Admin | `admin@smartqueue.test` |
| Super admin | `super@smartqueue.test` |

---

## 0. Before you start

The client talks to the API over HTTP; nothing in the app is faked. Start the server first:

```bash
cd server
npm run db:reset      # migrate + seed
npm run dev           # http://localhost:5000
```

Then the app:

```bash
cd mobile
flutter pub get
flutter run
```

On an Android emulator the default API address is `http://10.0.2.2:5000/api/v1` — the emulator's alias
for your machine's localhost. On iOS, a desktop build or Chrome, pass your own:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:5000/api/v1
```

Whatever the build is pointed at is printed under **Settings → Connection → API server**, so a
misconfigured build is obvious before you start debugging the wrong thing.

---

## 1. Customer

### 1.1 Getting an account

Open the app. The splash screen restores a saved session; if there is none you land on **Sign in**.

* **Register** takes first name, last name, email, phone and password. There is no role selector —
  every self-registration is a customer, because a screen that let you pick "admin" would be a
  security hole with a drop-down on it. Staff and administrators are created by an administrator.
* The password rules are checked on the device before the request goes out, and again by the server.
  The client's rules are a copy of the server's zod schema and there is a test that keeps them equal.
* **Forgot password** is honest about itself: the system sends no email. It tells you to ask an
  administrator at the desk, who can set a new password after checking your ID. Once you are signed
  in you can change it yourself from **Profile → Change password**.

### 1.2 Home

The Home tab is a summary of exactly two things:

* **Your queue** — if you hold a live ticket, a card showing the ticket number, how many people are
  ahead of you, your position and the estimated wait. Tap it to open the ticket. If you hold none,
  the card says *No active ticket* and points you at Services.
* **Available services** — the first few open services, with **Browse all** beside them.

Any published notice from the administration appears as a strip above both.

### 1.3 Taking a ticket

1. Go to **Services**. The list can be searched by name, code or category — the search runs on the
   server, so it finds things that are not on the current page.
2. Each card shows the service, its status and how many people are waiting. The **Join** button is
   disabled, with the reason written on the card, when the service is closed, outside its hours,
   inactive, or you already hold a ticket for it.
3. Tap a service to see its detail, or tap **Join** to open the **Join the queue** sheet. Before you
   commit to anything it shows four figures: *People waiting now*, *You would be* (the position you
   would take), *Estimated wait*, and *Counters open*.
4. Tap **Join queue**. The sheet is explicit that *your ticket number is issued by the server the
   moment you tap Join* — the app never invents one.

If the server refuses, the sheet says why in plain words rather than showing an error code:

| What happened | What you see |
| --- | --- |
| You already hold a ticket here | "You already hold a ticket for this service. Open My tickets to see it." |
| The queue hit its daily limit | "This queue has reached its limit for today. Please try again tomorrow." |
| A clerk paused the queue | "The queue is paused right now. Try again in a few minutes." |
| Closed for the day | "The queue is closed for today." |
| Before opening or after closing | "This service is outside its opening hours right now." |
| Already served here today | "You have already been served here today, and this service does not allow rejoining." |

### 1.4 Watching your place

The ticket screen is the one you leave open while you wait.

* A large **YOUR POSITION** number, with *Estimated wait* and *Now serving* beneath it.
* It refreshes itself every five seconds — the caption reads *Updates automatically*. You never pull
  to refresh, and the number moves while you watch.
* **View the queue board** opens the public board for that service: who is being served at which
  counter, and where you sit in the line.

When a clerk calls you the whole screen changes colour and says **It is your turn**, with
*Please go to Counter 3 now.* When they start serving, it becomes **You are being served**. When they
finish: *This visit is finished. Thank you for your patience.*

### 1.5 Leaving the queue

**Cancel my ticket** always asks first — *Leave the queue?* — and spells out the consequence: the
ticket will be cancelled and you will lose your place, and you would have to join again at the back.
The buttons are **Cancel ticket** and **Keep my place**, so a mis-tap cannot cost you your morning.

You cannot cancel once a clerk has called you — by then you are at the counter and it is theirs to
close. Some services switch cancellation off entirely; there the button is not offered, and the API
refuses it as well.

### 1.6 Alerts and profile

* **Alerts** is your inbox: you are notified when your turn is near, when you are called, and when
  the administration publishes a notice. The tab carries an unread badge that refreshes every thirty
  seconds. Tapping a notification marks it read; there is a **Mark all read**.
* **Profile** holds your details, **Change password**, and sign-out. Sign-out revokes the session on
  the server, not just on the device.
* **My tickets** lists everything you have ever taken, live ones first.

---

## 2. Staff

A clerk works exactly one service and one counter. Both are set by an administrator; nothing on the
staff side can change them, which is Rule 4 of the brief made physical.

### 2.1 The console

Signing in lands you on **Console**, titled with your service. Before anything else it tells you
where you stand:

* **No counter assigned** — *"You are not assigned to a service yet, so there is no queue to work. An
  administrator can assign you to a service and a counter."*
* Assigned to a service but not to a counter — you can watch the queue but not call from it.
* Assigned to both — the full console.

Four figures across the top: **Waiting now** (with the queue's state underneath), **You served
today**, **Average service**, **Skipped / no-show**. Below them, **Up next** — the next few tickets,
with **See all** into the Queue tab.

### 2.2 Working the queue

**Call next customer** takes the longest-waiting ticket, assigns it to your counter and notifies the
customer. When it is unavailable the button says why, rather than being mysteriously grey:

* "You need a counter before you can call anybody."
* "Your counter is off duty. Turn it back on to call the next customer."
* "Finish with FIN-014 first." — one customer per counter at a time.
* "Nobody is waiting right now."

With a customer at your counter the action bar offers only the moves the ticket's state allows:

| Ticket is | You can |
| --- | --- |
| Called | **Start serving** · **Call again** · **Skip** · **No-show** |
| Serving | **Complete** |
| Finished | nothing — *"This ticket is completed — nothing left to do."* |

The order is enforced by the server's state machine, not by hiding buttons: the app hides them
because they would be refused, and if two clerks race for the same ticket the second gets a clean
`409` and a refreshed screen.

**Skip** and **No-show** both confirm first, and the wording distinguishes them, because they mean
different things to the customer and to the report:

* Skip — *"They keep their ticket number but lose their place. Use this when somebody is not ready
  yet."*
* No-show — *"Use this when the customer did not come to the counter after being called."*

### 2.3 Going off duty

The counter tile has an on/off-duty switch: **Go off duty** parks your counter so the estimated wait
stops counting you as available. You cannot go off duty mid-customer — the switch is disabled with
*"Finish the customer at your counter first"*.

### 2.4 Queue, History and Stats

* **Queue** — the full waiting list, each row with its own **Call**, and a badge on the tab with the
  number waiting.
* **History** — every ticket you personally handled, filterable by date.
* **Stats** — your totals and a chart: served, average service time, skipped and no-shows. The
  figures come from the event log, so they follow *you*, not the counter you happened to sit at.

---

## 3. Administrator

The admin console is a navigation rail on a laptop, a drawer on a phone, with nine destinations:
**Dashboard · Services · Counters · Staff · Users · Queue monitor · Reports · Announcements · System
settings**. The last one is super-admin only.

### 3.1 Dashboard

The institution at a glance: tickets issued today, served, waiting now, average wait, the busiest
service, a bar chart of served-per-day and a donut of the ticket mix. It refreshes every fifteen
seconds.

### 3.2 Services

**New service** asks for a name, a **code** (the `FIN` in `FIN-001` — 2 to 8 letters or digits,
unique across the institution), a description, a category, an **average service time** in minutes
(the number the wait estimate is built on), a **daily capacity**, a **maximum queue size** and an
**alert when N away** threshold. From the row menu you can edit it, set its **opening hours** per
weekday, and tune its queue settings — maximum queue size, whether a customer may cancel, and
whether a customer already served today may rejoin.

Deleting a service deactivates it. History must survive, and destroying the row would take a day's
reporting with it; a permanent delete exists but only a super administrator can issue one, and only
against a service with nothing behind it.

### 3.3 Counters

**New counter** belongs to one service and carries a number unique within that service. A counter is
*available*, *busy* or *offline*. From the row menu: **Rename or renumber**, **Free this counter**
(releases whoever is posted there), **Delete**. **Staff Counter 3** posts a clerk to it — the picker
lists only active staff accounts, and says so when there are none.

### 3.4 Staff

The roster: name, email, **posting** (which service), counter and status. **Add staff** creates the
account and, optionally, posts them to a counter in one step. Releasing a clerk asks *Release from
counter?* first. A clerk with no posting is shown as **Not posted**; a suspended one as
**Suspended**.

### 3.5 Users

Every account, searchable by name, email or phone, filterable by role and status. Tapping one opens
the detail: contact details, when they joined, when they were last seen, and their activity —
tickets taken, completed, cancelled, and whether one is live right now.

The administration panel on that screen offers **Suspend** / **Reinstate**, **Deactivate**, **Change
role** and **Delete account**, each behind a confirmation. What you may do depends on who you are:

* You cannot administer your own account here — *"This is your own account. Use Profile to change
  it."*
* An admin cannot touch another admin or a super admin.
* Only a super admin can change roles, and the system will not let the last active super admin be
  demoted, suspended or deleted. That is defence in depth: the API refuses it whichever way you
  approach it.

### 3.6 Queue monitor

A read-only live board of every open queue: waiting, serving, now-serving numbers per counter. It
polls while it is on screen. Tap a service for its own board.

### 3.7 Announcements

**Compose** writes a notice; it starts as a **draft**, visible to nobody. **Publish** asks to confirm
— *Publish this notice?* — because publishing fans the notice out to every active user's inbox and
cannot be taken back. **Archive** retires it; **Edit** and **Delete** do what they say. Editing a
draft into a published state fans out exactly once.

### 3.8 Reports

Four tabs — **Daily**, **Services**, **Staff**, **Queues** — over any date range, with presets
(Today, Last 7 days, Last 30 days, This month, Custom) and a service filter.

| Report | Answers |
| --- | --- |
| Daily | How was the day: issued, served, cancelled, skipped, no-show, average wait, average service |
| Services | Which service is busy, which is slow, which is turning people away |
| Staff | Who handled how many, and how quickly |
| Queues | Peak queue length, average queue length, counter utilisation, peak hour |

**Export** downloads the server's own CSV — the app saves the bytes it is given rather than
rebuilding the file, so what a marker opens in a spreadsheet is the API's output. It lands in the
app's documents directory under `smartqueue-reports/`.

A figure that has no basis shows as **—**, not as zero: an average wait over tickets that never
reached a counter is *unknown*, and saying "0 minutes" would be a lie.

### 3.9 System settings (super admin)

Key/value settings for the institution, edited in place, with **Add setting** for a new one. Values
are stored as text because the table is deliberately schemaless. An ordinary admin gets `403` here,
and the destination is not even shown to them.

---

## 4. Super admin

Everything in §3, plus:

* **Change role** on any account — the only way a staff or admin account comes into existence.
* **System settings**.
* The protections in §3.5 apply to you too: you cannot remove the last active super admin, including
  by removing yourself. If you want out, promote somebody first.

---

## 5. What happens when things go wrong

The app never shows a stack trace or a raw error code. Every failure arrives as the same envelope
with a stable `code`, and the client turns it into a sentence — the table in §1.3 is a sample. Three
behaviours worth knowing as a user:

* **Offline** — an error screen with a wifi-off icon and **Try again**, which really re-asks the
  server rather than redrawing the last answer.
* **Session expired** — you are returned to sign-in with the reason stated, not dropped on a blank
  screen.
* **Somebody beat you to it** — if a clerk calls the ticket you were cancelling, or two clerks call
  the same customer, the loser gets a plain explanation and a refreshed screen. Nothing is
  double-counted; the database will not allow it.
