# Signing keystore — backup & restore (CRITICAL)

The Play upload key signs every WashPro release. **If it is lost, the app can
never be updated on Play Store again** (a new listing would be required).

## Backup made (Oct 22, 2026)
- Location (outside the repo): `~/WashPro-Backups/`
  - `upload-keystore.jks` — SHA-256 `e7d5b219aabd769232142382543a8bbd160a62507cd93f44a6fd08ffb369b118`
  - `key.properties` — SHA-256 `78cd563658669b60958dea6fe788749c347a2a62023f2e826e0ec8e15a784fe5`
- Permissions locked to owner-only (`chmod 600`). Passwords live ONLY inside
  `key.properties` — they are intentionally not written in this document.

## You must still do this (5 minutes)
Copy `~/WashPro-Backups/` to **two places off this laptop**:
1. A private Google Drive / iCloud folder (not shared), and
2. A USB pendrive kept somewhere safe.

A backup that only exists on the same laptop is not a backup.

## Restore (new machine)
1. Clone the project.
2. Copy `upload-keystore.jks` → `apps/customer-mobile/android/upload-keystore.jks`
3. Copy `key.properties` → `apps/customer-mobile/android/key.properties`
4. Verify integrity: `shasum -a 256 apps/customer-mobile/android/upload-keystore.jks`
   must match the checksum above.
5. Build: `flutter build appbundle --release` — signing works as before.

Both files are gitignored — never commit them, email them, or send them on chat apps.
