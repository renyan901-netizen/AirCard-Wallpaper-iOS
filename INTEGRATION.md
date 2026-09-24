# AirCard-Wallpaper-iOS

This working tree uses AirCard-iOS as the iOS 27 PosterBoard import base and adds a wallpaper resource catalog.

## Added

- `ios-app/WallpaperCatalog.swift`: loads `get_wallpaper.php`, supports search/tag filtering, resolves download URLs, stores downloaded `.tendies` files in Documents, and hands them to the existing `TendiesEngine` import path.
- `ios-app/WallpaperCatalogView.swift`: resource grid with preview, refresh, filtering, pagination, and download/import actions.
- A new `资源` tab in the existing SwiftUI tab bar.
- Xcode project references for both new Swift files.

## Build

Build on macOS with Xcode 16 or newer:

```sh
./build-ipa.sh
```

The script produces `build/AirCard-iOS.ipa` without an embedded signing identity. Sign it with the target sideloading tool before installing.

## Remaining device verification

The wallpaper list endpoint is verified live. The download endpoint requires the app's device fingerprint and server-side download authorization. The integration preserves the original app's endpoint and fingerprint flow, but the returned `.tendies` download must be verified on a real device because this Windows environment cannot build or run the iOS target.
