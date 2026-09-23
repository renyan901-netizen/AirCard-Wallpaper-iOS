# AirCard License Server

PHP 8 + SQLite backend for AirCard license keys.

## Deploy

1. Upload this directory to the same HTTPS PHP host used by the app, commonly as `/api`.
2. Copy `config.example.php` to `config.php` and set a long random `admin_password`. Do not commit `config.php`.
3. Enable PHP `pdo_sqlite` and make `data/` writable by PHP.
4. Open `license_admin.php` with HTTP Basic Auth. Generate a key, then redeem it in the app.

The app calls:

- `POST license_redeem.php` with `license_key` and `device_id`
- `POST license_status.php` with `device_id`

The default app URL is `https://wall-api.18ir.cn/api`. If the backend is deployed elsewhere, change `apiBaseURL` in `ios-app/LicenseManager.swift` before building.

## Security model

- Only SHA-256 hashes of license keys are stored.
- A key can be redeemed once and is bound to the first device ID.
- Repeating the same request on the same device is idempotent.
- The app checks the server before every wallpaper download.
- For strict enforcement, add the same `license_for_device()` check to the existing server-side download grant endpoint. Client-side checks alone can be removed from a modified IPA.
