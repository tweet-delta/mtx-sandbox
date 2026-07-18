# Test: an answers-only partial visit must show its work in Daily Logs.
#
# Regression test for the 2026-07-18 bug where stampDailyLog() recorded only
# checkbox (done === true) items, so a partial visit consisting of yes/no
# answers stamped an empty daily_logs.done_keys and the diary day rendered as
# a bare house name.
#
# How it works: boots the REAL route-checklist/index.html + cloud.js in
# headless Chrome (its own throwaway profile + local http server), with the
# Supabase client wrapped before cloud.js grabs it — fake signed-in tech, one
# fake house, every write captured instead of sent. Then calls the real
# cloud.saveVisit(payload, "in_progress") and asserts:
#   1. the daily_logs upsert carries the answered item keys, and
#   2. the real #logs screen renders those items in the day detail.
#
# Requirements: Python 3, `pip install websocket-client`, Chrome or Edge.
# Run:  python tests/daily-log-partial-visit.test.py
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
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port

# --- static server for the app (quiet: no request logs, ignore Chrome's
# abrupt keep-alive socket resets on Windows) ---
class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass

class QuietServer(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address): pass

http_port = free_port()
handler = functools.partial(QuietHandler, directory=APP_DIR)
httpd = QuietServer(("127.0.0.1", http_port), handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()

# --- Supabase-client wrapper injected before cloud.js runs ---
WRAPPER = r"""
(() => {
  const FAKE = { id: '00000000-e2e0-4000-8000-000000000001', email: 'e2e@test.local' };
  window.__ops = [];
  const HOUSES = [{ id: 'h-amble', name: 'Amble', equipment: '', notes: '',
                    info: null, general_notes: '', route_id: null }];
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
      window.__ops.push({ table: rec.table, method: rec.method,
                          payload: rec.payload, options: rec.options });
    }
    if (rec.method === 'insert' && rec.table === 'visits') return { data: { id: 'visit-e2e-1' }, error: null };
    if (rec.method !== 'select') return { data: rec.single ? {} : [], error: null };
    if (rec.table === 'houses')   return { data: HOUSES, error: null };
    if (rec.table === 'profiles') return { data: rec.single ? { role: 'tech', full_name: 'E2E' } : [], error: null };
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
    configurable: true,
    get(){ return real; },
    set(v){ real = wrap(v); },
  });
})();
"""

# --- headless Chrome + CDP plumbing ---
debug_port = free_port()
profile = tempfile.mkdtemp(prefix="cdp-profile-")
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
time.sleep(0.5)   # let loadRole/loadHouses settle

# An answers-only partial visit: two yes/no answers + a note, no checkboxes.
payload = {
  "houseName": "Amble", "date": time.strftime("%Y-%m-%d"), "counts": {}, "survey": {},
  "existingId": None,
  "items": [
    {"key": "mech-shutoffs", "done": None, "answer": "yes", "note": None, "doneOn": None, "value": None},
    {"key": "mech-clutter",  "done": None, "answer": "no",  "note": "messy", "doneOn": None, "value": None},
  ],
}
save_res = js(f"(async () => JSON.stringify(await window.cloud.saveVisit({json.dumps(payload)}, 'in_progress')))()")
print("saveVisit result:", save_res)

stamp_rows = json.loads(js("JSON.stringify((window.__ops||[]).filter(o => o.table==='daily_logs'))") or "[]")
done_keys = stamp_rows[0]["payload"].get("done_keys") if stamp_rows else None
t1 = done_keys is not None and "mech-shutoffs" in done_keys and "mech-clutter" in done_keys
print(f"TEST 1 (stamp records answered items): {'PASS' if t1 else 'FAIL'}  done_keys={done_keys}")

today = time.strftime("%Y-%m-%d")
auto_row = {"id": "log-e2e", "logDate": today, "kind": "auto", "visitId": "visit-e2e-1",
            "houseName": "Amble", "note": "", "doneKeys": done_keys or []}
js(f"window.cloud.listLogsInRange = async () => [{json.dumps(auto_row)}]; location.hash='#logs'; 'ok'")
time.sleep(1.0)
js(f"document.querySelector('[data-cal-day=\"{today}\"]').click(); 'ok'")
time.sleep(0.8)
detail = js("(() => { const d=document.querySelector('#logsScreen .cal-detail'); return d ? d.innerText : null; })()")
print("day detail:", json.dumps(detail))
t2 = bool(detail) and isinstance(detail, str) and ("shutoff" in detail.lower() or "clutter" in detail.lower())
print(f"TEST 2 (Daily Logs day detail shows the work): {'PASS' if t2 else 'FAIL'}")

proc.terminate()
httpd.shutdown()
print("RESULT:", "PASS" if (t1 and t2) else "FAIL")
sys.exit(0 if (t1 and t2) else 1)
