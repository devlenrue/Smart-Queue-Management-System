# Screenshots

This folder is empty on purpose. The project was built in an environment with no Flutter SDK, so
nothing here could be captured from the running app — and a mocked-up or AI-generated image of a
screen that has never been rendered is worse than no image at all.

Below is the shot list and the exact state to put the app in for each one. Taking them takes about
fifteen minutes with the seeded database.

## Setup

```bash
cd server && npm run db:reset && npm run dev
cd mobile && flutter pub get && flutter run
```

All demo accounts use the password `Password123!`.

Capture on a phone-sized device (the 360 dp layouts) unless the shot is marked **wide**, and add
`-wide` to the filename for those. Save as PNG.

## Shot list

| File | Screen | How to get there |
| --- | --- | --- |
| `01-login.png` | Sign in | Launch the app signed out |
| `02-services.png` | Service catalogue | Sign in as `john.doe@smartqueue.test` → **Services** |
| `03-join-sheet.png` | Join the queue sheet | Tap **Join** on Finance Office — shows the four figures before you commit |
| `04-ticket-waiting.png` | Ticket, waiting | Confirm the join; the position number and *Updates automatically* |
| `05-ticket-called.png` | Ticket, called | In a second window sign in as `jane.staff@smartqueue.test` and press **Call next customer**. The customer screen turns and reads **It is your turn** |
| `06-queue-board.png` | Public board | From the ticket, **View the queue board** |
| `07-cancel-confirm.png` | Cancel confirmation | Take a fresh ticket, tap **Cancel my ticket** — *Leave the queue?* |
| `08-staff-console.png` | Staff console | Sign in as staff; the four stats and **Up next** |
| `09-staff-serving.png` | Staff console, serving | Call a customer, then **Start serving** — the action bar shows only **Complete** |
| `10-staff-stats.png` | Staff statistics | Staff → **Stats** |
| `11-admin-dashboard-wide.png` | Admin dashboard **wide** | Sign in as `admin@smartqueue.test` on a desktop build or a tablet — shows the navigation rail and both charts |
| `12-admin-users.png` | User administration | Admin → **Users**; type a name in the search to show server-side search |
| `13-admin-counters.png` | Counters | Admin → **Counters** — available, busy and offline in one list |
| `14-admin-monitor.png` | Queue monitor | Admin → **Queue monitor** with at least one customer being served |
| `15-admin-reports-wide.png` | Reports **wide** | Admin → **Reports** → Daily, preset **Today** |
| `16-report-csv.png` | Exported CSV | Open the exported file from `smartqueue-reports/` in a spreadsheet |
| `17-empty-state.png` | An empty state | Admin → **Announcements** before composing anything — *Nothing composed yet* |
| `18-error-state.png` | An error state | Stop the API server and pull to refresh any list — the wifi-off icon and **Try again** |
| `19-responsive-trio.png` | The same screen at three widths | Services at 360, 768 and 1280 dp side by side. `flutter run -d chrome` and resize |
| `20-dark-mode.png` | Dark theme | Settings → Appearance → Dark |

Shots 17, 18 and 19 are the ones worth the most marks per second spent: they are the evidence for
§64 (loading and empty states), §65 (error handling) and the responsive requirement, and they are
the three a screenshot folder usually forgets.

## Referencing them

Once the files exist, the README's Screenshots section links them. Keep the filenames above so the
links do not have to change.
