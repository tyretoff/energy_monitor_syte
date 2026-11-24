const CACHE_NAME = "web-app-cache-v2";
const urlsToCache = [
  "/icon-192x192.png",
  "/icon-512x512.png"
];

self.addEventListener("install", event => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(urlsToCache);
    })
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keys => {
      return Promise.all(
        keys.map(key => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  // Не перехватываем и не кэшируем запросы к PHP или API
  if (event.request.url.includes('.php')) {
    return;
  }
  // Network first: сначала сеть, при сбое сети - кэш
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
