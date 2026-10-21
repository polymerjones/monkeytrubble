// Offline cache for the installed web app. Pages load network-first so updates show up on the next visit. Images and audio are
// served from the cache when there (stale-while-revalidate: a fresh copy is fetched in the background for next time), so a card
// flip never waits on the network; desktop Safari showed blank faces for seconds while each image re-checked the server.
const CACHE = 'monkeytrubble-v38';
const MEDIA = /\.(?:jpe?g|png|webp|gif|svg|mp3|wav|m4a|woff2?)$/i;
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE && !k.startsWith('monkeytrubble-')).map(k => caches.delete(k))))
    .then(() => caches.keys()).then(keys => Promise.all(keys.filter(k => k !== CACHE).map(async k => {
      // Carry the old cache's media over so the upgrade doesn't re-download every card, then drop it.
      const [from, to] = await Promise.all([caches.open(k), caches.open(CACHE)]);
      for (const req of await from.keys()) if (MEDIA.test(new URL(req.url).pathname)) { const res = await from.match(req); if (res) await to.put(req, res); }
      await caches.delete(k);
    }))).then(() => self.clients.claim())
));
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  if (req.headers.has('range')) return;
  const refresh = () => fetch(req).then(res => {
    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
    return res;
  });
  if (MEDIA.test(new URL(req.url).pathname)) {
    e.respondWith(caches.match(req).then(hit => {
      if (hit) { e.waitUntil(refresh().catch(() => {})); return hit; }
      return refresh();
    }));
    return;
  }
  e.respondWith(refresh().catch(() => caches.match(req)));
});
