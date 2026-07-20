# Test: cloud.js exposes the designer-home surface (job_titles.home_screen)
# after loadRole() runs, exercising the REAL route-checklist/index.html + cloud.js.
#
# Same harness as tests/tickets.test.py: boots the real app in headless Chrome
# with a local http server and a Supabase-client wrapper injected before
# cloud.js grabs window.supabase. The wrapper answers the profiles select with
# a signed-in supervisor whose job title has kind:'office', home_screen:'designer'.
#
# Asserts:
#   1. window.cloud.homeScreen === "designer" after loadRole() runs.
#   2. typeof window.cloud.setJobTitleHomeScreen === "function".
#   3. document.body has class "is-designer" (designer implies office too).
#
# Requirements: Python 3, `pip install websocket-client`, Chrome or Edge.
# Run:  python tests/designer-home.test.py
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

# One signed-in supervisor whose job title is kind:'office', home_screen:'designer'.
# loadRole() selects "role, job_titles(kind, home_screen)" from profiles — the
# mock returns that shape directly so we don't need to fake postgrest embeds.
WRAPPER = r"""
(() => {
  const FAKE = { id: '00000000-e2e0-4000-8000-000000000002', email: 'designer-e2e@test.local' };
  window.__ops = [];
  const PROFILE = {
    role: 'supervisor',
    job_titles: { kind: 'office', home_screen: 'designer' },
  };
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
    if (rec.method !== 'select') return { data: rec.single ? {} : [], error: null, count: 0 };
    if (rec.table === 'profiles') return { data: rec.single ? PROFILE : [], error: null };
    if (rec.table === 'houses') return { data: [], error: null };
    if (rec.table === 'routes') return { data: [], error: null };
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
profile = tempfile.mkdtemp(prefix="cdp-designer-home-")
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

# --- TEST 1: window.cloud.homeScreen === "designer" after loadRole() ---
home_screen = js("window.cloud.homeScreen")
t1 = home_screen == "designer"
results.append((f"window.cloud.homeScreen === 'designer' (got {home_screen!r})", t1))

# --- TEST 2: setJobTitleHomeScreen is exported as a function ---
setter_type = js("typeof window.cloud.setJobTitleHomeScreen")
t2 = setter_type == "function"
results.append((f"typeof window.cloud.setJobTitleHomeScreen === 'function' (got {setter_type!r})", t2))

# --- TEST 3: body carries is-designer (designer implies office too) ---
is_designer = js("document.body.classList.contains('is-designer')")
is_office = js("document.body.classList.contains('is-office')")
t3 = is_designer is True and is_office is True
results.append((f"body.is-designer and body.is-office both set (is-designer={is_designer}, is-office={is_office})", t3))

for label, ok in results:
    print(f"{'PASS' if ok else 'FAIL'}  {label}")

proc.terminate(); httpd.shutdown()
allok = all(ok for _, ok in results)
print("RESULT:", "PASS" if allok else "FAIL")
sys.exit(0 if allok else 1)
