# Smart Queue Management System

A beginner-friendly class project for a Smart Queue Management System.

## Build plan

The project is being built and checked in stages:

1. MySQL schema and seed data
2. Node.js + Express REST API
3. Flutter models, API client, Provider state, and screens
4. Integration testing, emulator setup, and presentation demo flow

## Project structure

```text
Smart-Queue-Management-System/
├── database/
│   ├── schema.sql
│   └── seed.sql
├── backend/                 # Added in the backend stage
│   ├── src/
│   │   ├── config/
│   │   ├── middleware/
│   │   ├── routes/
│   │   └── server.js
│   ├── .env.example
│   └── package.json
├── flutter_app/             # Added in the Flutter stage
│   ├── lib/
│   │   ├── models/
│   │   ├── providers/
│   │   ├── screens/
│   │   └── services/
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
└── README.md
```

## Stage 1: create the database

Requirements: MySQL 8.0 or newer.

From the repository root, run:

```bash
mysql -u root -p < database/schema.sql
mysql -u root -p < database/seed.sql
```

Or open both files in MySQL Workbench and run them in order.

The scripts create a database named `smart_queue_db` and these tables:

- `users`: customer, staff, and admin accounts. Passwords are stored as bcrypt hashes.
- `services`: queueable services and their fallback average service time.
- `tickets`: daily ticket numbers, queue status, timestamps, and staff audit fields.

Important schema rules:

- Ticket numbers are unique per service and operating day.
- A user cannot have two active tickets for the same service on the same day.
- Historical tickets remain available after they are served, cancelled, or skipped.
- Foreign keys protect services, users, and staff audit references.

### Seed accounts

The seed file creates the following accounts. The demo password for all of them is:

```text
password
```

| Email | Role |
| --- | --- |
| `admin@example.com` | admin |
| `staff@example.com` | staff |
| `alice@example.com` | customer |
| `bob@example.com` | customer |
| `carol@example.com` | customer |
| `david@example.com` | customer |

These are local demo credentials only. Use the API registration route for real accounts once the backend stage is added.

## Stage 2: backend API

The Express API is in `backend/`. See [`backend/README.md`](backend/README.md) for setup, route documentation, and curl examples.

```bash
cd backend
cp .env.example .env
npm install
npm run check
npm run dev
```

The Android emulator reaches a backend running on the development computer at `http://10.0.2.2:3000/api`.

## Stage 3: Flutter client

The Flutter client is in `flutter_app/`. It uses Material 3, Provider, and the `http` package only.

If the platform folders do not already exist, create them with Flutter installed:

```bash
cd flutter_app
flutter create .
flutter pub get
```

Start the app from VS Code or Android Studio, or use:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

For an iOS simulator use:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000/api
```

For a physical device, use the computer's LAN IP address. If Android blocks local HTTP traffic on a generated release configuration, add `android:usesCleartextTraffic="true"` to the local-development `<application>` element in `android/app/src/main/AndroidManifest.xml`. Do not use that setting for a production deployment without HTTPS.

The client includes:

- Login and customer registration
- Service list and join queue flow
- Queue number, current position, people ahead, current serving number, and estimated wait
- Seven-second queue polling
- In-app near-turn alert at two or three people ahead
- Leave queue and ticket history
- Staff/admin dashboard with call-next, complete, skip, add service, and soft-remove service actions

The JWT is intentionally kept in memory to avoid an extra storage package for this class project. Restarting the app requires logging in again.

## Testing checklist

1. Run MySQL schema and seed scripts.
2. Copy `backend/.env.example` to `backend/.env`, set the MySQL password and a JWT secret, then run `npm install`, `npm run check`, and `npm run dev`.
3. Confirm `GET http://localhost:3000/api/health` returns `{ "status": "ok", "database": "connected" }`.
4. Login as `alice@example.com` / `password`, list services, join Cashier, and check queue status.
5. Login as `staff@example.com` / `password`, open the staff dashboard, call next, complete or skip the ticket, and confirm the customer status updates after polling.
6. Login as `admin@example.com` / `password`, add a service and remove it again after its queue is empty.
7. Cancel a waiting customer ticket and confirm it appears as `cancelled` in history.
8. Register a new customer and verify the password is never returned by the API.

## Presentation demo flow and screenshots

Suggested four screenshots:

1. **Customer home:** service cards showing Cashier, Customer Service, and Enquiries.
2. **Customer queue status:** ticket number, current position, people ahead, estimated wait, and the near-turn alert.
3. **Staff dashboard:** a live queue with one serving ticket, waiting tickets, and the Call next/Complete controls.
4. **Completed flow:** customer ticket history showing served, skipped, or cancelled statuses.

A short live demo can use Alice as the customer and the seeded staff account: Alice joins Cashier, staff calls her ticket, the customer screen refreshes, staff marks it served, and the history screen records the completed ticket.

## Design assumptions

- Ticket numbering resets for each service each day; `ticket_date` records the operating day.
- The backend calculates the smart estimate from recent `served` tickets using `called_at` to `served_at`.
- `services.average_service_minutes` is the fallback until recent history is available.
- Queue status will be refreshed by the Flutter app every 5–10 seconds.
- Flutter talks only to the REST API; it never connects directly to MySQL.
