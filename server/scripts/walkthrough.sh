#!/usr/bin/env bash
#
# §85 success-criteria walkthrough, executed against a running API.
#
# Every figure printed below comes out of the database through the HTTP API —
# nothing here is faked, and nothing is written except through a documented
# endpoint. Two of the fourteen business rules are provoked on purpose so the
# refusals are visible alongside the happy path.
#
#   Usage:  npm run dev                      # in another terminal
#           bash scripts/walkthrough.sh      # optionally: BASE=http://host:port/api/v1
#
set -uo pipefail

BASE="${BASE:-http://localhost:5000/api/v1}"
PASS="${SEED_PASSWORD:-Password123!}"
SERVICE_ID="${SERVICE_ID:-1}"

py() { python3 -c "$1"; }
rule() { printf '\n\033[1m── %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }

token_of() { py "import sys,json;print(json.load(sys.stdin)['data']['token'])"; }

# ---------------------------------------------------------------------------

printf '\033[1m══ SmartQueue — §85 walkthrough against %s ══\033[0m\n' "$BASE"

rule "0. the API is up and the database is reachable"
curl -s "$BASE/system/health" | py "
import sys,json
d=json.load(sys.stdin)['data']
print('   status %s · database %s (%s) · timezone %s' % (d['status'], d['database'], d['dialect'], d['timezone']))"

rule "0b. the office may be shut — widen today's hours for the run"
# Nothing else in this script writes configuration. This one step exists so a
# marker can run the walkthrough at any hour; the original hours are restored
# at the end, and the refusal it avoids (OUTSIDE_SERVICE_HOURS) is a real rule
# you can see for yourself by running this outside 08:00–17:00 without it.
ADMIN=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"admin@smartqueue.test\",\"password\":\"$PASS\"}" | token_of)
export DOW=$(date +%w)
ORIGINAL=$(curl -s "$BASE/services/$SERVICE_ID/hours" -H "Authorization: Bearer $ADMIN" | py "
import sys,json,os
dow=int(os.environ['DOW'])
rows=json.load(sys.stdin)['data']
print(json.dumps(next((r for r in rows if r['dayOfWeek']==dow), {})))")
echo "   today's hours were: $ORIGINAL"
curl -s -X PUT "$BASE/services/$SERVICE_ID/hours" -H "Authorization: Bearer $ADMIN" \
  -H 'Content-Type: application/json' \
  -d "{\"hours\":[{\"dayOfWeek\":$DOW,\"openingTime\":\"00:00\",\"closingTime\":\"23:59\",\"isClosed\":false}]}" | py "
import sys,json;d=json.load(sys.stdin);print('  ', d.get('message'), '→ 00:00–23:59 for this run')"

restore_hours() {
  echo "$ORIGINAL" | py "
import sys,json,os,urllib.request
row=json.load(sys.stdin)
if not row: raise SystemExit
body=json.dumps({'hours':[{'dayOfWeek':row['dayOfWeek'],'openingTime':row['openingTime'],
                           'closingTime':row['closingTime'],'status':row['status']}]}).encode()
req=urllib.request.Request(os.environ['BASE']+'/services/'+os.environ['SERVICE_ID']+'/hours',
                           data=body, method='PUT',
                           headers={'Content-Type':'application/json',
                                    'Authorization':'Bearer '+os.environ['ADMIN']})
try:
    urllib.request.urlopen(req).read()
    print('   hours restored to %s–%s' % (row['openingTime'], row['closingTime']))
except Exception as e:
    print('   could not restore hours:', e)"
}
export BASE SERVICE_ID ADMIN
trap restore_hours EXIT

rule "1. a new customer registers"
STAMP=$(date +%H%M%S)
EMAIL="walkthrough-$STAMP@smartqueue.test"
REG=$(curl -s -X POST "$BASE/auth/register" -H 'Content-Type: application/json' -d "{
  \"firstName\":\"Amina\",\"lastName\":\"Walker\",\"email\":\"$EMAIL\",
  \"phone\":\"+2547${STAMP}11\",\"password\":\"Password123!\",\"confirmPassword\":\"Password123!\"}")
CUSTOMER=$(echo "$REG" | token_of) || { echo "$REG"; exit 1; }
echo "$REG" | py "
import sys,json
u=json.load(sys.stdin)['data']['user']
print('   %s · role %s · id %s' % (u['fullName'], u['role'], u['id']))
assert u['role']=='customer', 'self-registration must always be a customer'"

rule "2. browses the service catalogue — live figures, server-computed"
curl -s "$BASE/services" -H "Authorization: Bearer $CUSTOMER" | py "
import sys,json
for s in json.load(sys.stdin)['data']:
    q=s.get('queue') or {}
    print('   %-4s %-18s %-8s waiting %-3s serving %-3s now %-8s est %s min' % (
        s['code'], s['name'], s['status'], q.get('waitingCount'), q.get('servingCount'),
        q.get('nowServing') or '—', q.get('estimatedWaitMinutes')))"

rule "3. joins a queue — the server issues the ticket number"
JOIN=$(curl -s -X POST "$BASE/services/$SERVICE_ID/queue/join" \
  -H "Authorization: Bearer $CUSTOMER" -H 'Content-Type: application/json' -d '{}')
echo "$JOIN" | py "
import sys,json
d=json.load(sys.stdin)
if not d['success']: print('   ', d['code'], '—', d['message']); raise SystemExit(1)
t=d['data']['ticket']; p=d['data'].get('position') or {}
print('  ', d['message'])
print('   %s · %s · position %s · %s ahead · est %s min over %s counters' % (
    t['ticketNumber'], t['status'], p.get('position'), p.get('peopleAhead'),
    p.get('estimatedWaitMinutes'), p.get('activeCounters')))" || exit 1
TICKET_ID=$(echo "$JOIN" | py "import sys,json;print(json.load(sys.stdin)['data']['ticket']['id'])")
TICKET_NO=$(echo "$JOIN" | py "import sys,json;print(json.load(sys.stdin)['data']['ticket']['ticketNumber'])")

rule "4. Rule 1 — one active ticket per user per service"
curl -s -X POST "$BASE/services/$SERVICE_ID/queue/join" \
  -H "Authorization: Bearer $CUSTOMER" -H 'Content-Type: application/json' -d '{}' | py "
import sys,json
d=json.load(sys.stdin)
print('   refused %s — %s' % (d['code'], d['message']))
assert d['code']=='DUPLICATE_ACTIVE_TICKET'"

rule "5. tracks position"
curl -s "$BASE/tickets/$TICKET_ID/position" -H "Authorization: Bearer $CUSTOMER" | py "
import sys,json
d=json.load(sys.stdin)['data']
print('   position %s · %s ahead · est %s min · now serving %s' % (
    d.get('position'), d.get('peopleAhead'), d.get('estimatedWaitMinutes'), d.get('nowServing')))"

rule "6. a clerk signs in — Rule 5 stops a second ticket at a busy counter"
STAFF=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"jane.staff@smartqueue.test\",\"password\":\"$PASS\"}" | token_of)
DASH=$(curl -s "$BASE/dashboard/staff" -H "Authorization: Bearer $STAFF")
echo "$DASH" | py "
import sys,json
d=json.load(sys.stdin)['data']
c=d.get('counter') or {}; t=d.get('currentTicket') or {}; q=d.get('queue') or {}
print('   %s at %s · holding %s (%s) · %s waiting' % (
    (d.get('service') or {}).get('name'), c.get('name'),
    t.get('ticketNumber') or '—', t.get('status') or '—', q.get('waitingCount')))"
HELD=$(echo "$DASH" | py "import sys,json;t=(json.load(sys.stdin)['data'].get('currentTicket') or {});print(t.get('id',''))")
if [ -n "$HELD" ]; then
  curl -s -X POST "$BASE/tickets/call-next" -H "Authorization: Bearer $STAFF" \
    -H 'Content-Type: application/json' -d "{\"serviceId\":$SERVICE_ID}" | py "
import sys,json
d=json.load(sys.stdin)
print('   refused %s — %s' % (d['code'], d['message']))"
  curl -s -X POST "$BASE/tickets/$HELD/complete" -H "Authorization: Bearer $STAFF" \
    -H 'Content-Type: application/json' -d '{}' | py "
import sys,json;print('   cleared —', json.load(sys.stdin).get('message'))"
fi

rule "7. the clerk works down the queue to our ticket"
for _ in $(seq 1 40); do
  R=$(curl -s -X POST "$BASE/tickets/call-next" -H "Authorization: Bearer $STAFF" \
        -H 'Content-Type: application/json' -d "{\"serviceId\":$SERVICE_ID}")
  OK=$(echo "$R" | py "import sys,json;print(json.load(sys.stdin)['success'])")
  if [ "$OK" != "True" ]; then echo "$R" | py "import sys,json;d=json.load(sys.stdin);print('   stopped:',d['code'],'—',d['message'])"; break; fi
  N=$(echo "$R"  | py "import sys,json;print(json.load(sys.stdin)['data']['ticket']['ticketNumber'])")
  I=$(echo "$R"  | py "import sys,json;print(json.load(sys.stdin)['data']['ticket']['id'])")
  note "called $N"
  [ "$N" = "$TICKET_NO" ] && break
  curl -s -X POST "$BASE/tickets/$I/start"    -H "Authorization: Bearer $STAFF" -H 'Content-Type: application/json' -d '{}' >/dev/null
  curl -s -X POST "$BASE/tickets/$I/complete" -H "Authorization: Bearer $STAFF" -H 'Content-Type: application/json' -d '{}' >/dev/null
done

rule "8. the customer's screen has changed"
curl -s "$BASE/tickets/$TICKET_ID" -H "Authorization: Bearer $CUSTOMER" | py "
import sys,json
d=json.load(sys.stdin)['data']; t=d.get('ticket',d)
print('   %s is now %s' % (t['ticketNumber'], t['status']))"

rule "9. called → serving → completed"
curl -s -X POST "$BASE/tickets/$TICKET_ID/start" -H "Authorization: Bearer $STAFF" \
  -H 'Content-Type: application/json' -d '{}' | py "
import sys,json;d=json.load(sys.stdin);print('  ', d['message'], '→', d['data']['ticket']['status'])"
curl -s -X POST "$BASE/tickets/$TICKET_ID/complete" -H "Authorization: Bearer $STAFF" \
  -H 'Content-Type: application/json' -d '{}' | py "
import sys,json;d=json.load(sys.stdin);print('  ', d['message'], '→', d['data']['ticket']['status'])"

rule "10. the state machine refuses to complete it twice"
curl -s -X POST "$BASE/tickets/$TICKET_ID/complete" -H "Authorization: Bearer $STAFF" \
  -H 'Content-Type: application/json' -d '{}' | py "
import sys,json
d=json.load(sys.stdin)
print('   refused %s — %s' % (d['code'], d['message']))
assert d['code']=='INVALID_STATE_TRANSITION'"

rule "11. another customer cannot read this ticket"
OTHER=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"john.doe@smartqueue.test\",\"password\":\"$PASS\"}" | token_of)
curl -s "$BASE/tickets/$TICKET_ID" -H "Authorization: Bearer $OTHER" | py "
import sys,json;d=json.load(sys.stdin);print('   refused %s — %s' % (d['code'], d['message']))"

rule "12. the customer was notified at each step"
curl -s "$BASE/notifications?limit=5" -H "Authorization: Bearer $CUSTOMER" | py "
import sys,json
d=json.load(sys.stdin)['data']
print('   %s unread' % d.get('unreadCount'))
for n in d['notifications']:
    print('   · %-30s %s' % (n['title'], n['message'][:58]))"

rule "13. the administrator's daily report reflects it"
curl -s "$BASE/reports/daily" -H "Authorization: Bearer $ADMIN" | py "
import sys,json
t=json.load(sys.stdin)['data']['totals']
print('   issued %s · served %s · cancelled %s · skipped %s · no-show %s' % (
    t['issued'], t['served'], t['cancelled'], t['skipped'], t['noShow']))
print('   average wait %s min · average service %s min' % (
    t['averageWaitMinutes'], t['averageServiceMinutes']))"

rule "14. …and exports as the server's own CSV"
curl -s "$BASE/reports/daily?format=csv" -H "Authorization: Bearer $ADMIN" -D /tmp/sq-head.txt -o /tmp/sq-report.csv
grep -i '^content-\(type\|disposition\)' /tmp/sq-head.txt | tr -d '\r' | sed 's/^/   /'
head -3 /tmp/sq-report.csv | tr -d '\r' | sed 's/^/   /'

rule "15. a customer may not read a report"
curl -s "$BASE/reports/daily" -H "Authorization: Bearer $CUSTOMER" | py "
import sys,json;d=json.load(sys.stdin);print('   refused %s — %s' % (d['code'], d['message']))"

printf '\n\033[1m══ walkthrough complete ══\033[0m\n'
