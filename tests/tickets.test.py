# Test: the maintenance-tickets feature renders and drives correctly against a
# mocked Supabase, exercising the REAL route-checklist/index.html + cloud.js.
#
# Same harness as tests/daily-log-partial-visit.test.py: boots the real app in
# headless Chrome with a local http server and a Supabase-client wrapper injected
# before cloud.js grabs window.supabase. The wrapper answers ticket queries with
# canned rows and records every insert / rpc so we can assert on them.
#
# Asserts:
#   1. createTicket() inserts a tickets row with the chosen fields.
#   2. The #tickets screen renders the canned tickets and correct chip counts
#      (urgent = 1, stale 30d+ = 1).
#   3. Clicking "✔ Completed" on the detail screen fires rpc set_ticket_status
#      with 'completed'.
#   4. The in-visit panel lists ONLY the visited house's open tickets.
#
# Requirements: Python 3, `pip install websocket-client`, Chrome or Edge.
# Run:  python tests/tickets.test.py
import json, os, subprocess, sys, tempfile, threading, time, urllib.request
import functools, http.server, socket

try:
    import websocket
except ImportError:
    sys.exit("Missing dependency: pip install websocket-client")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(REPO, "route-checklist")

BROWSERS = [
    os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"),
    os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
    os.path.expandvars(r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"),
    os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"),
    "/usr/bin/google-chrome", "/usr/bin/chromium",
]
CHROME = os.environ.get("CHROME") or next((p for p in BROWSERS if os.path.exists(p)), None)
if not CHROME:
    sys.exit("Chrome/Edge not found; set the CHROME env var to the browser exe")

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close(); return port

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
class QuietServer(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address): pass

http_port = free_port()
handler = functools.partial(QuietHandler, directory=APP_DIR)
httpd = QuietServer(("127.0.0.1", http_port), handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()

# Two houses; three tickets — one urgent + one 45-day-stale at Amble, one at
# Birch — so the chip counts and the visit-panel house filter are both testable.
WRAPPER = r"""
(() => {
  const FAKE = { id: '00000000-e2e0-4000-8000-000000000001', email: 'e2e@test.local' };
  window.__ops = [];
  const HOUSES = [
    { id: 'h-amble', name: 'Amble', equipment: '', notes: '', info: null, general_notes: '', route_id: null },
    { id: 'h-birch', name: 'Birch', equipment: '', notes: '', info: null, general_notes: '', route_id: null },
  ];
  const now = Date.now();
  const iso = ms => new Date(ms).toISOString();
  const day = 86400000;
  const TICKETS = [
    { id: 'tk-1', title: 'Water heater leaking', description: 'drip', category: 'Plumbing',
      level: 'resident', status: 'in_progress', priority: 'urgent', requested_by_role: 'rs',
      assigned_to: FAKE.id, created_at: iso(now-2*day), updated_at: iso(now-1*day), completed_at: null,
      houses: { name: 'Amble' }, submitter: { full_name: 'Sup' }, assignee: { full_name: 'E2E' } },
    { id: 'tk-2', title: 'Old garage seal', description: '', category: 'House Visit List',
      level: 'resident', status: 'new', priority: 'normal', requested_by_role: 'maintenance',
      assigned_to: null, created_at: iso(now-45*day), updated_at: iso(now-45*day), completed_at: null,
      houses: { name: 'Amble' }, submitter: { full_name: 'Sup' }, assignee: null },
    { id: 'tk-3', title: 'Birch handrail loose', description: '', category: 'Railings',
      level: 'resident', status: 'new', priority: 'normal', requested_by_role: 'staff',
      assigned_to: null, created_at: iso(now-3*day), updated_at: iso(now-3*day), completed_at: null,
      houses: { name: 'Birch' }, submitter: { full_name: 'Sup' }, assignee: null },
  ];
  function makeQuery(table) {
    const rec = { table, method: 'select', payload: null, options: null, single: false };
    const q = {};
    ['select','eq','neq','gte','lte','gt','lt','in','is','not','order','limit','filter','range','ilike','or']
      .forEach(m => q[m] = () => q);
    ['insert','update','upsert','delete'].forEach(m => q[m] = (payload, options) => {
      rec.method = m; rec.payload = payload; rec.options = options; return q;
    });
    q.single = () => { rec.single = true; return q; };
    q.maybeSingle = () => { rec.single = true; return q; };
    q.then = (res, rej) => Promise.resolve(result(rec)).then(res, rej);
    return q;
  }
  function result(rec) {
    if (rec.method !== 'select') {
      window.__ops.push({ table: rec.table, method: rec.method, payload: rec.payload, options: rec.options });
    }
    if (rec.method === 'insert' && rec.table === 'tickets') return { data: { id: 'tk-new' }, error: null };
    if (rec.method !== 'select') return { data: rec.single ? {} : [], error: null, count: 0 };
    if (rec.table === 'houses')   return { data: HOUSES, error: null };
    if (rec.table === 'profiles') return { data: rec.single ? { role: 'tech', full_name: 'E2E' } : [], error: null };
    if (rec.table === 'tickets') {
      if (rec.single) return { data: { ...TICKETS[0], ticket_notes: [] }, error: null };
      return { data: TICKETS, error: null, count: TICKETS.filter(t=>t.status!=='completed').length };
    }
    if (rec.table === 'notifications') return { data: rec.single ? null : [], error: null, count: 0 };
    return { data: rec.single ? null : [], error: null, count: 0 };
  }
  function wrap(client) {
    client.auth.getUser = async () => ({ data: { user: FAKE }, error: null });
    client.auth.getSession = async () => ({ data: { session: { user: FAKE } }, error: null });
    client.auth.onAuthStateChange = (cb) => {
      setTimeout(() => cb('SIGNED_IN', { user: FAKE }), 0);
      return { data: { subscription: { unsubscribe(){} } } };
    };
    client.rpc = async (name, args) => { window.__ops.push({ rpc: name, args }); return { data: 0, error: null }; };
    client.from = (table) => makeQuery(table);
    return client;
  }
  let real;
  Object.defineProperty(window, 'supabase', {
    configurable: true, get(){ return real; }, set(v){ real = wrap(v); },
  });
})();
"""

debug_port = free_port()
profile = tempfile.mkdtemp(prefix="cdp-tickets-")
proc = subprocess.Popen([
    CHROME, "--headless=new", f"--remote-debugging-port={debug_port}",
    "--remote-allow-origins=*", f"--user-data-dir={profile}",
    "--no-first-run", "--window-size=1000,1400", "about:blank",
], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def get_ws_url():
    for _ in range(50):
        try:
            with urllib.request.urlopen(f"http://localhost:{debug_port}/json/list") as r:
                for t in json.load(r):
                    if t.get("type") == "page":
                        return t["webSocketDebuggerUrl"]
        except Exception:
            pass
        time.sleep(0.3)
    raise RuntimeError("Chrome debug port never came up")

ws = websocket.create_connection(get_ws_url(), timeout=30)
msg_id = 0
def send(method, params=None):
    global msg_id
    msg_id += 1
    ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == msg_id:
            return m.get("result", {})

def js(expr):
    r = send("Runtime.evaluate", {"expression": expr, "awaitPromise": True, "returnByValue": True})
    if "exceptionDetails" in r:
        return {"__error__": r["exceptionDetails"].get("exception", {}).get("description", str(r["exceptionDetails"]))}
    return r.get("result", {}).get("value")

send("Page.enable"); send("Runtime.enable")
send("Page.addScriptToEvaluateOnNewDocument", {"source": WRAPPER})
send("Page.navigate", {"url": f"http://localhost:{http_port}/index.html"})

for _ in range(60):
    if js("document.readyState==='complete' && !!window.cloud && !document.body.classList.contains('locked')"):
        break
    time.sleep(0.5)
else:
    proc.terminate(); sys.exit("FATAL: app never reached signed-in state")
time.sleep(0.6)

results = []

# --- TEST 1: createTicket inserts a tickets row with chosen fields ---
payload = {"houseName": "Amble", "level": "resident", "title": "New screen door",
           "description": "latch broken", "category": "Doors", "priority": "normal",
           "requestedByRole": "rs"}
js(f"(async()=>{{await window.cloud.createTicket({json.dumps(payload)});}})()")
ins = json.loads(js("JSON.stringify((window.__ops||[]).filter(o=>o.table==='tickets'&&o.method==='insert'))") or "[]")
t1 = bool(ins) and ins[0]["payload"].get("title") == "New screen door" and ins[0]["payload"].get("category") == "Doors"
results.append(("createTicket inserts chosen fields", t1))

# --- TEST 2: #tickets renders cards + chip counts (urgent 1, stale 1) ---
js("location.hash='#tickets'; 'ok'"); time.sleep(1.0)
n_cards = js("document.querySelectorAll('#ticketsBody .tk-card').length")
urgent_chip = js("(()=>{const c=document.querySelector('#ticketsBody [data-tk-filter=\"urgent\"] b');return c?c.textContent:null;})()")
stale_chip = js("(()=>{const c=document.querySelector('#ticketsBody [data-tk-filter=\"stale\"] b');return c?c.textContent:null;})()")
t2 = (n_cards or 0) >= 3 and urgent_chip == "1" and stale_chip == "1"
results.append((f"#tickets renders (cards={n_cards}, urgent={urgent_chip}, stale={stale_chip})", t2))

# --- TEST 3: ✔ Completed on detail fires rpc set_ticket_status(completed) ---
js("window.__ops=[]; location.hash='#ticket/tk-1'; 'ok'"); time.sleep(1.0)
js("(()=>{const b=[...document.querySelectorAll('#ticketDetailBody [data-tk-status]')].find(x=>x.dataset.tkStatus==='completed');if(b)b.click();return !!b;})()")
time.sleep(0.6)
rpc_ops = json.loads(js("JSON.stringify((window.__ops||[]).filter(o=>o.rpc==='set_ticket_status'))") or "[]")
t3 = bool(rpc_ops) and rpc_ops[0]["args"].get("p_status") == "completed"
results.append(("Completed fires set_ticket_status rpc", t3))

# --- TEST 4: visit panel lists only the visited house's open tickets ---
# Pick Amble in the checklist, then read the panel. Amble has 2 open tickets;
# Birch's ticket must NOT appear.
js("location.hash='#visit'; 'ok'"); time.sleep(0.6)
# selectHouse is closure-private, so drive the house picker like a tech would.
js("""(()=>{
  const btn=[...document.querySelectorAll('#app [data-pick-house]')].find(b=>b.dataset.pickHouse==='Amble');
  if(btn) btn.click();
})()""")
time.sleep(1.2)
panel_titles = js("""(()=>{
  const p=document.getElementById('visitTicketsBody');
  return p?[...p.querySelectorAll('.tk-title')].map(x=>x.textContent).join('|'):null;
})()""")
t4 = bool(panel_titles) and "Water heater leaking" in panel_titles and "Birch handrail" not in (panel_titles or "")
results.append((f"visit panel scoped to house (titles={panel_titles})", t4))

for label, ok in results:
    print(f"{'PASS' if ok else 'FAIL'}  {label}")

proc.terminate(); httpd.shutdown()
allok = all(ok for _, ok in results)
print("RESULT:", "PASS" if allok else "FAIL")
sys.exit(0 if allok else 1)
