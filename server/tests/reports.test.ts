/**
 * Phase 8 verification — the four management reports and the CSV export
 * (§41, §53, docs/api.md §13).
 *
 * The fixture is built through the real API — customers join, clerks call,
 * serve, complete and skip, a customer cancels — and only then are the
 * ticket timestamps rewritten to a known clock. That keeps the state machine
 * honest (every row got there through a legal transition) while making every
 * average, peak and percentage something a marker can check by hand.
 *
 * The day, on the Finance queue, two counters:
 *
 *   ticket  joined  called  started  completed  outcome     wait  service
 *   FIN-001  09:00   09:10    09:11      09:21  completed     10       10
 *   FIN-002  09:05   09:25    09:26      09:36  completed     20       10
 *   FIN-003  09:10   09:40        —          —  skipped       30        —
 *   FIN-004  09:15       —        —          —  cancelled      —        —
 *
 * and one ticket left waiting on the Registrar queue (REG-001, 09:30).
 *
 *   issued 4 · served 2 · cancelled 1 · skipped 1 · no-show 0
 *   average wait     = (10 + 20 + 30) / 3 = 20.0 min   (cancelled never waited *for a counter*)
 *   average service  = (10 + 10) / 2      = 10.0 min
 *   peak queue       = 3 (09:15 — FIN-002, FIN-003, FIN-004 all waiting)
 *   waiting minutes  = 10 + 20 + 30 + 5   = 65
 *   open window      = 09:00 → 09:40      = 40 min
 *   average queue    = 65 / 40            = 1.6
 *   utilisation      = 20 / (2 × 40)      = 25%
 *   peak hour        = 09:00–10:00
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { getDb } from '../src/db';
import { closeDatabase, freshDatabase } from './helpers/db';
import { act, bearer, callNext, clearQueueData, createUserAndLogin, join, setupService } from './helpers/api';
import type { TestService, TestUser } from './helpers/api';
import { todayDate } from '../src/utils/datetime';
import { csvCell, toCsv } from '../src/utils/csv';

let app: Express;

beforeAll(async () => {
  await freshDatabase();
  app = createApp();
});

afterAll(async () => {
  await closeDatabase();
});

const today = todayDate();
const at = (hhmm: string): string => `${today} ${hhmm}:00`;

interface Fixture {
  admin: TestUser;
  superAdmin: TestUser;
  clerkOne: TestUser;
  clerkTwo: TestUser;
  customer: TestUser;
  fin: TestService;
  reg: TestService;
  tickets: { one: number; two: number; three: number; four: number; five: number };
}

/** Rewrites one ticket's clock. Anything omitted is set to NULL. */
async function setTimes(
  ticketId: number,
  times: { joined: string; called?: string; started?: string; completed?: string; cancelled?: string },
): Promise<void> {
  await getDb().execute(
    `UPDATE queue_tickets
        SET joined_at = ?, called_at = ?, service_started_at = ?, completed_at = ?, cancelled_at = ?
      WHERE id = ?`,
    [
      at(times.joined),
      times.called ? at(times.called) : null,
      times.started ? at(times.started) : null,
      times.completed ? at(times.completed) : null,
      times.cancelled ? at(times.cancelled) : null,
      ticketId,
    ],
  );
}

async function buildDay(): Promise<Fixture> {
  const fin = await setupService(app, { code: 'FIN', name: 'Finance Office', counters: 2 });
  const reg = await setupService(app, { code: 'REG', name: 'Registrar', counters: 1 });

  const admin = await createUserAndLogin(app, { role: 'admin', firstName: 'Ada', lastName: 'Admin' });
  const superAdmin = await createUserAndLogin(app, { role: 'super_admin', firstName: 'Sam', lastName: 'Super' });

  const [clerkOne, clerkTwo] = fin.staff;
  const customers = await Promise.all([
    createUserAndLogin(app, { firstName: 'Cust', lastName: 'One' }),
    createUserAndLogin(app, { firstName: 'Cust', lastName: 'Two' }),
    createUserAndLogin(app, { firstName: 'Cust', lastName: 'Three' }),
    createUserAndLogin(app, { firstName: 'Cust', lastName: 'Four' }),
    createUserAndLogin(app, { firstName: 'Cust', lastName: 'Five' }),
  ]);

  // Joins happen in order, so sequence numbers match the table above.
  const ids: number[] = [];
  for (const customer of customers.slice(0, 4)) {
    const response = await join(app, fin.serviceId, customer);
    expect(response.status).toBe(201);
    ids.push(response.body.data.ticket.id);
  }

  // FIN-001 — clerk one serves it through to completion.
  const firstCall = await callNext(app, clerkOne, fin.serviceId);
  expect(firstCall.status).toBe(200);
  expect(firstCall.body.data.ticket.id).toBe(ids[0]);
  expect((await act(app, clerkOne, ids[0], 'start')).status).toBe(200);
  expect((await act(app, clerkOne, ids[0], 'complete')).status).toBe(200);

  // FIN-002 — clerk two, at the second counter.
  const secondCall = await callNext(app, clerkTwo, fin.serviceId);
  expect(secondCall.body.data.ticket.id).toBe(ids[1]);
  expect((await act(app, clerkTwo, ids[1], 'start')).status).toBe(200);
  expect((await act(app, clerkTwo, ids[1], 'complete')).status).toBe(200);

  // FIN-003 — called by clerk one, then skipped.
  const thirdCall = await callNext(app, clerkOne, fin.serviceId);
  expect(thirdCall.body.data.ticket.id).toBe(ids[2]);
  expect((await act(app, clerkOne, ids[2], 'skip')).status).toBe(200);

  // FIN-004 — the customer gives up before anyone calls them.
  expect((await act(app, customers[3], ids[3], 'cancel')).status).toBe(200);

  // REG-001 — still waiting when the report runs.
  const regJoin = await join(app, reg.serviceId, customers[4]);
  expect(regJoin.status).toBe(201);

  await setTimes(ids[0], { joined: '09:00', called: '09:10', started: '09:11', completed: '09:21' });
  await setTimes(ids[1], { joined: '09:05', called: '09:25', started: '09:26', completed: '09:36' });
  await setTimes(ids[2], { joined: '09:10', called: '09:40' });
  await setTimes(ids[3], { joined: '09:15', cancelled: '09:20' });
  await setTimes(regJoin.body.data.ticket.id, { joined: '09:30' });

  // Finance closes for the day, which fixes its window at 09:00–09:40 and
  // keeps every figure below independent of the clock the test runs on.
  // The registrar's queue stays open, so it exercises the other branch.
  await getDb().execute("UPDATE queues SET status = 'closed' WHERE service_id = ?", [fin.serviceId]);

  return {
    admin,
    superAdmin,
    clerkOne,
    clerkTwo,
    customer: customers[0],
    fin,
    reg,
    tickets: { one: ids[0], two: ids[1], three: ids[2], four: ids[3], five: regJoin.body.data.ticket.id },
  };
}

const report = (kind: string, viewer: TestUser, query = '') =>
  request(app).get(`/api/v1/reports/${kind}${query}`).set('Authorization', bearer(viewer.token));

// ---------------------------------------------------------------------------
// Access control (§41 — reports are a management view)
// ---------------------------------------------------------------------------

describe('Report access control', () => {
  let fixture: Fixture;

  beforeAll(async () => {
    await clearQueueData();
    fixture = await buildDay();
  });

  const kinds = ['daily', 'services', 'staff', 'queues'];

  it.each(kinds)('rejects an anonymous request for /reports/%s', async (kind) => {
    const response = await request(app).get(`/api/v1/reports/${kind}`);
    expect(response.status).toBe(401);
  });

  it.each(kinds)('rejects a customer asking for /reports/%s', async (kind) => {
    const response = await report(kind, fixture.customer);
    expect(response.status).toBe(403);
  });

  it.each(kinds)('rejects a clerk asking for /reports/%s', async (kind) => {
    const response = await report(kind, fixture.clerkOne);
    expect(response.status).toBe(403);
  });

  it.each(kinds)('allows an administrator to run /reports/%s', async (kind) => {
    const response = await report(kind, fixture.admin);
    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
  });

  it('allows a super administrator to run a report', async () => {
    const response = await report('daily', fixture.superAdmin);
    expect(response.status).toBe(200);
  });
});

// ---------------------------------------------------------------------------
// Query validation
// ---------------------------------------------------------------------------

describe('Report query validation', () => {
  let admin: TestUser;

  beforeAll(async () => {
    await clearQueueData();
    admin = await createUserAndLogin(app, { role: 'admin' });
  });

  it('rejects a malformed date', async () => {
    const response = await report('daily', admin, '?from=2026-13-40');
    expect(response.status).toBe(422);
    expect(response.body.code).toBe('VALIDATION_ERROR');
    expect(response.body.errors[0].field).toBe('from');
  });

  it('rejects a range that ends before it starts', async () => {
    const response = await report('daily', admin, '?from=2026-09-30&to=2026-09-01');
    expect(response.status).toBe(422);
    expect(response.body.errors[0].message).toMatch(/cannot be before/i);
  });

  it('rejects a range longer than a year', async () => {
    const response = await report('daily', admin, '?from=2024-01-01&to=2026-01-01');
    expect(response.status).toBe(422);
    expect(response.body.errors[0].message).toMatch(/at most 366 days/i);
  });

  it('rejects an unknown export format', async () => {
    const response = await report('daily', admin, '?format=pdf');
    expect(response.status).toBe(422);
  });

  it('rejects a non-numeric service filter', async () => {
    const response = await report('services', admin, '?serviceId=finance');
    expect(response.status).toBe(422);
  });

  it('defaults the range to today', async () => {
    const response = await report('daily', admin);
    expect(response.status).toBe(200);
    expect(response.body.data.range).toEqual({ from: today, to: today });
  });

  it('treats a single `from` as a one-day range', async () => {
    const response = await report('daily', admin, '?from=2026-01-15');
    expect(response.body.data.range).toEqual({ from: '2026-01-15', to: '2026-01-15' });
  });

  it('returns an empty report for a day with no queues', async () => {
    const response = await report('daily', admin, '?from=2001-01-01&to=2001-01-31');
    expect(response.status).toBe(200);
    expect(response.body.data.rows).toEqual([]);
    expect(response.body.data.totals).toMatchObject({ issued: 0, served: 0, averageWaitMinutes: null });
  });
});

// ---------------------------------------------------------------------------
// §41.1 Daily summary
// ---------------------------------------------------------------------------

describe('Daily report', () => {
  let fixture: Fixture;

  beforeAll(async () => {
    await clearQueueData();
    fixture = await buildDay();
  });

  it('returns one row per service that opened a queue', async () => {
    const response = await report('daily', fixture.admin);
    expect(response.status).toBe(200);

    const rows = response.body.data.rows;
    expect(rows).toHaveLength(2);
    expect(rows.map((row: { serviceCode: string }) => row.serviceCode).sort()).toEqual(['FIN', 'REG']);
    expect(rows.every((row: { date: string }) => row.date === today)).toBe(true);
  });

  it('counts every disposition of the finance queue', async () => {
    const response = await report('daily', fixture.admin);
    const finance = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'FIN');

    expect(finance).toMatchObject({
      issued: 4,
      served: 2,
      cancelled: 1,
      skipped: 1,
      noShow: 0,
    });
  });

  it('averages wait and service time from the real timestamps', async () => {
    const response = await report('daily', fixture.admin);
    const finance = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'FIN');

    // (10 + 20 + 30) / 3 and (10 + 10) / 2
    expect(finance.averageWaitMinutes).toBe(20);
    expect(finance.averageServiceMinutes).toBe(10);
  });

  it('leaves averages null where nobody reached a counter', async () => {
    const response = await report('daily', fixture.admin);
    const registrar = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'REG');

    expect(registrar).toMatchObject({ issued: 1, served: 0, averageWaitMinutes: null, averageServiceMinutes: null });
  });

  it('totals the whole range, not the rounded rows', async () => {
    const response = await report('daily', fixture.admin);

    expect(response.body.data.totals).toEqual({
      issued: 5,
      served: 2,
      cancelled: 1,
      skipped: 1,
      noShow: 0,
      averageWaitMinutes: 20,
      averageServiceMinutes: 10,
    });
  });

  it('narrows to a single service when asked', async () => {
    const response = await report('daily', fixture.admin, `?serviceId=${fixture.fin.serviceId}`);

    expect(response.body.data.rows).toHaveLength(1);
    expect(response.body.data.rows[0].serviceCode).toBe('FIN');
    expect(response.body.data.totals.issued).toBe(4);
  });

  it('excludes days outside the range', async () => {
    const response = await report('daily', fixture.admin, '?from=2020-01-01&to=2020-01-31');
    expect(response.body.data.rows).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// §41.2 Service performance
// ---------------------------------------------------------------------------

describe('Service report', () => {
  let fixture: Fixture;

  beforeAll(async () => {
    await clearQueueData();
    fixture = await buildDay();
  });

  it('ranks services by customers served', async () => {
    const response = await report('services', fixture.admin);
    const rows = response.body.data.rows;

    expect(rows).toHaveLength(2);
    expect(rows[0].serviceCode).toBe('FIN');
    expect(rows[0].customersServed).toBe(2);
    expect(rows[1].serviceCode).toBe('REG');
    expect(rows[1].customersServed).toBe(0);
  });

  it('reports the busiest hour of the day', async () => {
    const response = await report('services', fixture.admin);
    const finance = response.body.data.rows[0];

    expect(finance.peakHour).toBe(9);
    expect(finance.peakHourLabel).toBe('09:00–10:00');
  });

  it('reports the longest the queue ever got', async () => {
    const response = await report('services', fixture.admin);
    const finance = response.body.data.rows[0];

    // 09:15 — FIN-002, FIN-003 and FIN-004 are all waiting at once.
    expect(finance.peakQueueLength).toBe(3);
  });

  it('counts a service that saw nobody, rather than dropping it', async () => {
    const quiet = await setupService(app, { code: 'LIB', name: 'Library', counters: 0 });
    expect(quiet.serviceId).toBeGreaterThan(0);

    const response = await report('services', fixture.admin);
    const library = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'LIB');

    expect(library).toMatchObject({ issued: 0, customersServed: 0, peakQueueLength: 0, peakHour: null });
    expect(library.averageWaitMinutes).toBeNull();
  });

  it('expresses completion as a percentage of tickets issued', async () => {
    const response = await report('services', fixture.admin);
    const finance = response.body.data.rows[0];

    expect(finance.completionRate).toBe(50); // 2 of 4
  });
});

// ---------------------------------------------------------------------------
// §41.3 Staff performance
// ---------------------------------------------------------------------------

describe('Staff report', () => {
  let fixture: Fixture;

  beforeAll(async () => {
    await clearQueueData();
    fixture = await buildDay();
  });

  it('credits each clerk with the tickets they handled', async () => {
    const response = await report('staff', fixture.admin);
    const rows = response.body.data.rows;

    expect(rows).toHaveLength(2);
    const [first, second] = rows;
    expect(first.ticketsServed).toBe(1);
    expect(second.ticketsServed).toBe(1);
    expect(rows.map((row: { ticketsSkipped: number }) => row.ticketsSkipped).sort()).toEqual([0, 1]);
  });

  it('counts every action, not just completions', async () => {
    const response = await report('staff', fixture.admin);
    const clerkOne = response.body.data.rows.find(
      (row: { staffId: number }) => row.staffId === fixture.clerkOne.id,
    );

    // called + started + completed for FIN-001, called + skipped for FIN-003
    expect(clerkOne.ticketsHandled).toBe(5);
    expect(clerkOne.ticketsServed).toBe(1);
    expect(clerkOne.ticketsSkipped).toBe(1);
    expect(clerkOne.averageServiceMinutes).toBe(10);
  });

  it('names the clerk and the service they worked', async () => {
    const response = await report('staff', fixture.admin);
    const clerkTwo = response.body.data.rows.find(
      (row: { staffId: number }) => row.staffId === fixture.clerkTwo.id,
    );

    expect(clerkTwo.staffName).toBe('Staff Number2');
    expect(clerkTwo.serviceCode).toBe('FIN');
    expect(clerkTwo.ticketsHandled).toBe(3);
  });

  it('leaves customers out of the staff report', async () => {
    const response = await report('staff', fixture.admin);
    const ids = response.body.data.rows.map((row: { staffId: number }) => row.staffId);

    expect(ids).not.toContain(fixture.customer.id);
  });

  it('omits clerks who did nothing in the range', async () => {
    const response = await report('staff', fixture.admin);
    const ids = response.body.data.rows.map((row: { staffId: number }) => row.staffId);

    // The registrar's clerk never called anybody.
    expect(ids).not.toContain(fixture.reg.staff[0].id);
  });

  it('narrows to one clerk when asked', async () => {
    const response = await report('staff', fixture.admin, `?staffId=${fixture.clerkTwo.id}`);

    expect(response.body.data.rows).toHaveLength(1);
    expect(response.body.data.rows[0].staffId).toBe(fixture.clerkTwo.id);
  });

  it('weights the overall average by tickets served', async () => {
    const response = await report('staff', fixture.admin);

    expect(response.body.data.totals).toEqual({
      staff: 2,
      ticketsHandled: 8,
      ticketsServed: 2,
      ticketsSkipped: 1,
      ticketsNoShow: 0,
      averageServiceMinutes: 10,
    });
  });
});

// ---------------------------------------------------------------------------
// §41.4 Queue analytics
// ---------------------------------------------------------------------------

describe('Queue report', () => {
  let fixture: Fixture;

  beforeAll(async () => {
    await clearQueueData();
    fixture = await buildDay();
  });

  it('reports when a finished queue opened and closed', async () => {
    const response = await report('queues', fixture.admin);
    const finance = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'FIN');

    expect(finance.status).toBe('closed');
    expect(new Date(finance.openedAt).getHours()).toBe(9);
    expect(new Date(finance.openedAt).getMinutes()).toBe(0);
    expect(new Date(finance.closedAt).getMinutes()).toBe(40);
  });

  it('leaves the closing time empty while a queue is still open', async () => {
    const response = await report('queues', fixture.admin);
    const registrar = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'REG');

    expect(registrar.status).toBe('waiting');
    expect(registrar.closedAt).toBeNull();
  });

  it('measures the peak and average queue length', async () => {
    const response = await report('queues', fixture.admin);
    const finance = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'FIN');

    expect(finance.peakQueue).toBe(3);
    // 65 waiting minutes over a 40 minute window
    expect(finance.averageQueue).toBe(1.6);
  });

  it('measures counter utilisation over the open window', async () => {
    const response = await report('queues', fixture.admin);
    const finance = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'FIN');

    // 20 minutes of service across 2 counters × 40 minutes open
    expect(finance.countersUsed).toBe(2);
    expect(finance.utilisationPercent).toBe(25);
  });

  it('reports a queue nobody has been served from as idle', async () => {
    const response = await report('queues', fixture.admin);
    const registrar = response.body.data.rows.find((row: { serviceCode: string }) => row.serviceCode === 'REG');

    expect(registrar).toMatchObject({ issued: 1, served: 0, utilisationPercent: 0 });
    expect(registrar.peakQueue).toBe(1);
  });

  it('never reports an average longer than the peak', async () => {
    // The two are measured over the same window or they are meaningless:
    // an average of 61 people in a queue that peaked at 7 is a bug, not a
    // busy morning.
    const response = await report('queues', fixture.admin);

    for (const row of response.body.data.rows) {
      expect(row.averageQueue).toBeLessThanOrEqual(row.peakQueue);
      expect(row.utilisationPercent).toBeLessThanOrEqual(100);
      expect(row.utilisationPercent).toBeGreaterThanOrEqual(0);
    }
  });

  it('summarises the range', async () => {
    const response = await report('queues', fixture.admin);

    expect(response.body.data.totals).toMatchObject({ queues: 2, issued: 5, served: 2, peakQueue: 3 });
  });
});

// ---------------------------------------------------------------------------
// CSV export (§41 — "export to CSV")
// ---------------------------------------------------------------------------

describe('CSV export', () => {
  let fixture: Fixture;

  beforeAll(async () => {
    await clearQueueData();
    fixture = await buildDay();
  });

  it('returns a downloadable file rather than the JSON envelope', async () => {
    const response = await report('daily', fixture.admin, '?format=csv');

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/text\/csv/);
    expect(response.headers['content-disposition']).toContain(`smartqueue-daily-${today}.csv`);
    expect(response.text.startsWith('{')).toBe(false);
  });

  it('writes the documented header row', async () => {
    const response = await report('daily', fixture.admin, '?format=csv');
    const [header] = response.text.split('\r\n');

    expect(header).toBe(
      'Date,Service,Code,Issued,Served,Cancelled,Skipped,No show,Average wait (min),Average service (min)',
    );
  });

  it('writes one line per row, with the same numbers as the JSON', async () => {
    const json = await report('daily', fixture.admin);
    const csv = await report('daily', fixture.admin, '?format=csv');

    const lines = csv.text.trimEnd().split('\r\n');
    expect(lines).toHaveLength(json.body.data.rows.length + 1);

    const finance = lines.find((line) => line.includes('Finance Office'));
    expect(finance).toBe(`${today},Finance Office,FIN,4,2,1,1,0,20,10`);
  });

  it('leaves an empty cell where an average does not exist', async () => {
    const response = await report('queues', fixture.admin, '?format=csv');
    const registrar = response.text.split('\r\n').find((line) => line.includes('Registrar'));

    expect(registrar).toContain('Registrar,REG,waiting,');
  });

  it('names the file after the range it covers', async () => {
    const response = await report('services', fixture.admin, '?from=2026-01-01&to=2026-01-31&format=csv');

    expect(response.headers['content-disposition']).toContain('smartqueue-services-2026-01-01_2026-01-31.csv');
  });

  it.each(['daily', 'services', 'staff', 'queues'])('exports /reports/%s as CSV', async (kind) => {
    const response = await report(kind, fixture.admin, '?format=csv');

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/text\/csv/);
    expect(response.text.split('\r\n')[0]).toMatch(/^[A-Z]/);
  });
});

// ---------------------------------------------------------------------------
// The CSV writer itself
// ---------------------------------------------------------------------------

describe('CSV writer', () => {
  it('quotes only the fields that need it', () => {
    expect(csvCell('Finance')).toBe('Finance');
    expect(csvCell('Finance, Office')).toBe('"Finance, Office"');
    expect(csvCell('He said "hello"')).toBe('"He said ""hello"""');
    expect(csvCell('line\nbreak')).toBe('"line\nbreak"');
    expect(csvCell(' padded ')).toBe('" padded "');
  });

  it('writes an empty field for null and undefined, never the word', () => {
    expect(csvCell(null)).toBe('');
    expect(csvCell(undefined)).toBe('');
    expect(csvCell(0)).toBe('0');
  });

  it('separates records with CRLF and ends the file with one', () => {
    const csv = toCsv(
      [
        { header: 'Name', value: (row: { name: string; total: number | null }) => row.name },
        { header: 'Total', value: (row: { name: string; total: number | null }) => row.total },
      ],
      [
        { name: 'Finance, Office', total: 4 },
        { name: 'Registrar', total: null },
      ],
    );

    expect(csv).toBe('Name,Total\r\n"Finance, Office",4\r\nRegistrar,\r\n');
  });
});
