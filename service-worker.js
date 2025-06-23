const CACHE_NAME = "web-app-cache-v1";
const urlsToCache = [
  "index.html",
  "icon-192x192.png",
  "icon-512x512.png"
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      console.log("Opened cache. Starting to cache files individually for debugging.");
      for (const url of urlsToCache) {
        try {
          // Use {cache: 'reload'} to ensure the request goes to the network
          const response = await fetch(url, { cache: 'reload' });
          if (!response.ok) {
            // Log the error and re-throw to fail the installation
            console.error(`Failed to fetch ${url}: status ${response.status}`);
            throw new TypeError(`Bad response status for ${url}: ${response.status}`);
          }
          await cache.put(url, response);
          console.log(`Successfully cached: ${url}`);
        } catch (error) {
          console.error(`Failed to cache ${url}.`, error);
          // Re-throw the error to ensure the service worker installation fails
          throw error;
        }
      }
    })
  );
});

self.addEventListener("fetch", event => {
  event.respondWith(
    caches.match(event.request).then(response => {
      return response || fetch(event.request);
    })
  );
});
