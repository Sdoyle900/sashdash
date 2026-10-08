// SashDash service worker — caches the app shell so it opens instantly on site
// and survives a weak signal. Live data and PDFs (Supabase) always go to the network.
const CACHE_NAME = 'sashdash-shell-v3';
const SHELL_FILES = ['./index.html', './manifest.json', './icon-192.png', './icon-512.png', './sdwindows-logo.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) =>
    Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;          // never touch Supabase
  const isShell = SHELL_FILES.some((f) => url.pathname.endsWith(f.replace('./', '/'))) || url.pathname.endsWith('/');
  if (!isShell) return;
  event.respondWith(
    fetch(req, { cache: 'no-store' }).then((res) => {   // always get the newest app when online
      const copy = res.clone();
      caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
      return res;
    }).catch(() => caches.match(req).then((r) => r || caches.match('./index.html')))
  );
});

// ── Phone notifications ─────────────────────────────────────────────
self.addEventListener('push', (event) => {
  let d = {}; try { d = event.data ? event.data.json() : {}; } catch (e) { d = { body: event.data && event.data.text() }; }
  event.waitUntil(self.registration.showNotification(d.title || 'SashDash', {
    body: d.body || '', icon: 'icon-192.png', badge: 'icon-192.png',
    tag: d.tag, renotify: true, data: { url: d.url || './' }
  }));
});
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || './';
  event.waitUntil((async () => {
    const wins = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of wins) {
      if (w.url.includes('/sashdash')) { await w.focus(); w.postMessage({ openUrl: url }); return; }
    }
    await clients.openWindow(url);
  })());
});
