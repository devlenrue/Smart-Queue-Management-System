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

## Design assumptions

- Ticket numbering resets for each service each day; `ticket_date` records the operating day.
- The backend will calculate the smart estimate from recent `served` tickets using `called_at` to `served_at`.
- `services.average_service_minutes` is the fallback until recent history is available.
- Queue status will be refreshed by the Flutter app every 5–10 seconds.
- Flutter talks only to the REST API; it never connects directly to MySQL.
