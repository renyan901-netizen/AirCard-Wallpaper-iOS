# AirCard-Wallpaper-iOS

This working tree uses AirCard-iOS as the iOS 27 PosterBoard import base and adds a wallpaper resource catalog.

## Added

- `ios-app/WallpaperCatalog.swift`: loads `get_wallpaper.php`, supports search/tag filtering, resolves download URLs, stores downloaded `.tendies` files in Documents, and hands them to the existing `TendiesEngine` import path.
- `ios-app/WallpaperCatalogView.swift`: resource grid with preview, refresh, filtering, pagination, and download/import actions.
- A new `资源` tab in the existing SwiftUI tab bar.
- Xcode project references for both new Swift files.

## Verified Download Flow

Verified on 2026-09-23 against the live wallpaper service. The resource download must keep the original app's two-step authorization flow:

1. Build a 32-character lowercase hexadecimal device fingerprint. Prefer `UIDevice.current.identifierForVendor`; retain the original app's Keychain value as a fallback. The original Keychain identifiers are service `com.mutually.wallpaper.device` and account `device_fp`.
2. Encode the authorization card ID as `Base64URL(\"<card_id>|<Unix timestamp seconds>\")`. Use standard Base64, replace `+` with `-` and `/` with `_`, and keep any trailing `=` padding.
3. Request `GET https://wall-api.18ir.cn/api/free_unlock_grant.php` with the encoded card ID and the same `device_fp`:

   ```text
   card_id=<Base64URL(card_id|timestamp)>&device_fp=<32-hex-fingerprint>
   ```

   Continue only when the JSON response contains `ok: true`.
4. Request `GET https://wall-api.18ir.cn/api/get_download_url.php` with the raw numeric card ID and the same device fingerprint:

   ```text
   card_id=<numeric-card-id>&device_fp=<32-hex-fingerprint>
   ```

   The download URL is returned as `down_url` (or an equivalent nested URL field).
5. Download the `.tendies` package, save it under Documents, and pass it to `TendiesEngine` for import.

Calling `get_download_url.php` directly, or sending the raw numeric ID to `free_unlock_grant.php`, returns `ad_unlock_required` or `invalid card_id`. The grant step is required even in the no-ads build; it is a server-side authorization step, not an ad UI step.

## iOS 27 Import Path

On iOS 27, the original app can download the `.tendies` package but its legacy PosterBoard container installation reports that the container is unavailable. The merged app therefore keeps the downloaded package in the app container and uses AirCard's pairing/local-loopback import path. The recovery scan searches Documents, Application Support, and Caches for `.tendies` files and imports them into the existing AirCard storage.

## Built-In LocalDevVPN

The LocalDevVPN loopback tunnel is now embedded in the same IPA. The integration includes a `NetworkExtension` packet-tunnel target and the main app's in-app manager:

- Main App Bundle ID: `com.mutually.wallpaper`
- Packet Tunnel Bundle ID: `com.mutually.wallpaper.LocalDevVPN`
- Interface address: `10.7.1.1/32`
- Peer/device address: `10.7.0.1/32` by default, configurable from the Pairing page
- Main App entitlement: `allow-vpn` and `packet-tunnel-provider`
- Extension entitlement: `packet-tunnel-provider`

The Pairing page creates the VPN profile on first use, saves it to iOS VPN preferences, starts the packet tunnel, and then AirCard can continue directly to pairing and wallpaper flashing. The separate LocalDevVPN app is no longer required.

The packet provider uses the upstream LocalDevVPN reflection behavior: it installs only the peer route, excludes the default route, and reflects IPv4 source/destination addresses inside the packet loop. The upstream project is credited in `THIRD-PARTY-NOTICES.md`.

The signing profile must allow Network Extension packet-tunnel capabilities for both Bundle IDs. A self-signed IPA without those entitlements may install but cannot create or start the VPN configuration.

## Build

Build on macOS with Xcode 16 or newer:

```sh
./build-ipa.sh
```

The script produces `build/AirCard-iOS.ipa` without an embedded signing identity. Sign it with the target sideloading tool before installing.

## Verification Status

The list endpoint, two-step authorization flow, `.tendies` download, and combined iOS 27 workflow were verified on a real device. The unsigned build was produced by GitHub Actions and still requires the user's normal signing step before installation.
