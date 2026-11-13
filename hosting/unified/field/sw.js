/* ZYLO Field — scoped shell cache only; never cache private Firestore/API data.
 * Scope is registration.scope (/field/ on unified hosting, / on legacy sites).
 */
const CACHE = "zylo-field-v3";

function basePath() {
  try {
    return new URL(self.registration.scope).pathname;
  } catch {
    return "/";
  }
}

function shellUrls() {
  const b = basePath();
  return [
    b,
    `${b}index.html`,
    `${b}manifest.webmanifest`,
    `${b}icon.svg`,
    `${b}icon-maskable.svg`,
  ];
}

function underScope(pathname) {
  const b = basePath();
  if (b === "/") {
    return !pathname.startsWith("/admin") && !pathname.startsWith("/app") && !pathname.startsWith("/field");
  }
  return pathname === b.slice(0, -1) || pathname.startsWith(b);
}

function relativePath(pathname) {
  const b = basePath();
  if (b === "/") return pathname;
  if (pathname === b.slice(0, -1)) return "/";
  if (pathname.startsWith(b)) return `/${pathname.slice(b.length)}`;
  return pathname;
}

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches
      .open(CACHE)
      .then((c) => c.addAll(shellUrls()))
      .then(() => self.skipWaiting())
      .catch(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

function isShellRequest(url) {
  if (url.origin !== self.location.origin) return false;
  if (!underScope(url.pathname)) return false;
  const rel = relativePath(url.pathname);
  return (
    rel === "/" ||
    rel === "/index.html" ||
    rel.startsWith("/assets/") ||
    rel === "/manifest.webmanifest" ||
    rel.endsWith(".svg") ||
    rel.endsWith(".png") ||
    rel.endsWith(".ico") ||
    rel.endsWith(".css") ||
    (rel.endsWith(".js") && !rel.includes("firebase"))
  );
}

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  if (!underScope(url.pathname)) return;

  const indexKey = `${basePath()}index.html`;

  if (!isShellRequest(url)) {
    e.respondWith(fetch(req).catch(() => caches.match(indexKey)));
    return;
  }

  if (relativePath(url.pathname) === "/" || relativePath(url.pathname) === "/index.html" || req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(indexKey, copy));
          return res;
        })
        .catch(() => caches.match(indexKey).then((r) => r || caches.match(basePath()))),
    );
    return;
  }

  e.respondWith(
    caches.match(req).then((hit) => {
      if (hit) return hit;
      return fetch(req).then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      });
    }),
  );
});
