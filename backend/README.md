# Smart Queue REST API

This folder contains the Node.js + Express API. Flutter communicates with this API; it never connects directly to MySQL.

## Run locally

Requirements:

- Node.js 18 or newer
- MySQL 8.0 or newer
- The root `database/schema.sql` and `database/seed.sql` have been run

```bash
cd backend
cp .env.example .env
# Edit .env with the local MySQL username, password, and a JWT secret.
npm install
npm run check
npm run dev
```

The API listens on `http://0.0.0.0:3000`. On an Android emulator, Flutter must call:

```text
http://10.0.2.2:3000/api
```

An iOS simulator can normally use:

```text
http://127.0.0.1:3000/api
```

For a physical device, use the computer's LAN IP address instead of either emulator address.

## Authentication

Register and login return a JWT. Send it on protected requests:

```text
Authorization: Bearer YOUR_TOKEN
```

Passwords are hashed with bcrypt before they are stored.

## API routes

### Public routes

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/api/health` | Check API and database connectivity |
| `POST` | `/api/auth/register` | Create a customer account |
| `POST` | `/api/auth/login` | Login as a customer, staff member, or admin |
| `GET` | `/api/services` | List active services |

Register body:

```json
{
  "fullName": "Jane Customer",
  "email": "jane@example.com",
  "password": "secret123"
}
```

Login body:

```json
{
  "email": "jane@example.com",
  "password": "secret123"
}
```

### Customer/protected routes

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/api/auth/me` | Return the current user |
| `POST` | `/api/queues/join` | Join a service queue; body is `{ "serviceId": 1 }` |
| `GET` | `/api/queues/service/:serviceId/status` | Current ticket position and estimate |
| `GET` | `/api/queues/history?limit=50` | Current user's ticket history |
| `POST` | `/api/queues/:ticketId/cancel` | Leave a waiting or serving queue |

Queue status includes:

- `currentServing`
- `myTicket`
- `currentPosition`
- `peopleAhead`
- `estimatedWaitMinutes`
- `averageServiceMinutes`
- active queue tickets

The average uses completed tickets from the last 30 days. If none exist, the service's configured fallback average is used.

### Staff/admin routes

Staff and admins can operate queues:

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/api/admin/queues/:serviceId` | View the live queue |
| `POST` | `/api/admin/queues/:serviceId/call-next` | Call the earliest waiting ticket |
| `POST` | `/api/admin/tickets/:ticketId/complete` | Mark a serving ticket as served |
| `POST` | `/api/admin/tickets/:ticketId/skip` | Skip a waiting or serving no-show |

Admins can also manage services:

| Method | Route | Purpose |
| --- | --- | --- |
| `POST` | `/api/services` | Add a service |
| `DELETE` | `/api/services/:serviceId` | Soft-remove an empty service |

## Quick curl flow

```bash
# Login and copy the token from the response.
curl -X POST http://localhost:3000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"alice@example.com","password":"password"}'

# List services.
curl http://localhost:3000/api/services

# Join service 1. Replace TOKEN with the login token.
curl -X POST http://localhost:3000/api/queues/join \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer TOKEN' \
  -d '{"serviceId":1}'

# Poll queue status for service 1.
curl http://localhost:3000/api/queues/service/1/status \
  -H 'Authorization: Bearer TOKEN'
```
