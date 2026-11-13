# ZYLO Field — Firebase Hosting & DNS

## Verified Hosting (project `wash-pro-7f3b1`)

| Role | Hosting target | Site ID | Default URL |
|------|----------------|---------|-------------|
| Worker (ZYLO Field) | `worker` | **`wash-pro-worker`** | https://wash-pro-worker.web.app |
| Admin (ZYLO Control) | `admin` | `wash-pro-admin` | https://wash-pro-admin.web.app |
| Customer (ZYLO) | `app` | `wash-pro-customer` | https://wash-pro-customer.web.app |

> Note: the live site ID is `wash-pro-worker` (with hyphens), not `washpro-worker`. Do not create a duplicate site unless intentionally migrating.

Custom domain (production): **https://field.zyloo.co.in**

## Build & deploy worker only

```bash
cd apps/worker-pwa
npm install
npm run build
cd ../..
firebase deploy --only hosting:worker --project wash-pro-7f3b1
```

From a writable directory (e.g. `apps/customer-mobile`) if the CLI cannot write `firebase-debug.log` at the repo root.

## Connect custom domain (Console)

1. Firebase Console → Hosting → site **`wash-pro-worker`** → **Add custom domain**.
2. Enter `field.zyloo.co.in`.
3. Firebase shows the required DNS records (typically an **A** / **AAAA** or **CNAME**, plus a short-lived TXT verification record).  
   **Use only the values Firebase displays for your project** — do not invent IPs or CNAMEs.
4. In your DNS provider for `zyloo.co.in`, add those exact records.
5. Wait for SSL provisioning (can take minutes to hours). Status must show **Connected**.

## Verify after DNS

```bash
# Should resolve via Firebase Hosting once connected
curl -sI https://field.zyloo.co.in | head
curl -sI https://wash-pro-worker.web.app | head
```

Confirm page title / PWA name is **ZYLO Field** and auth still talks to project `wash-pro-7f3b1`.

## Preserve other apps

Never run a blanket `firebase deploy --only hosting` unless you intend to publish admin + customer + worker together. Prefer:

```bash
firebase deploy --only hosting:worker --project wash-pro-7f3b1
```
