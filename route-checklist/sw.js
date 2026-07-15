// sw.js — minimal service worker. Two jobs:
//   1. Make the app installable to the phone home screen.
//   2. Keep a cached copy of the app shell so it still opens with no signal.
// Strategy is "network-first" for our own files, so while online you always get
// the freshest version; the cache is only a fallback when offline.

const CACHE = "route-checklist-v23";
const SHELL = [
  "./", "index.html", "house-data.js", "supabase-config.js", "cloud.js",
  "manifest.webmanifest", "icon-192.png", "icon-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.map((k) => (k === CACHE ? null : caches.delete(k)))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  // Only our own GET requests — never cache Supabase or CDN calls.
  if (req.method !== "GET" || new URL(req.url).origin !== self.location.origin) return;
  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req).then((r) => r || caches.match("index.html")))
  );
});
