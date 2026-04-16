## Unreleased

- Add hardened Android network download pipeline: strict `2xx` status validation, redirect cap (`3`), bounded transfer size, and MP4 signature validation before caching.
- Add stable network failure error codes (`1001..1005`) for invalid URL, HTTP status, size exceeded, invalid media, and network I/O.
- Add policy unit tests for min download floor, URL sanitization, and MP4 signature validation.

## 0.1.1

- Change Android plugin package/namespace from `com.tencent.vap_player_android` to `app.misi.vap_player_android`.
- Move Kotlin source/test package paths to match the new Android namespace.

## 0.1.0

- Initial Android federated implementation release for `flutter_vap_player`.
- Implements platform view rendering and playback controls.
- Supports asset, file, and network playback requests.
- Supports VAPX text/tag replacement and async image resource loading.
- Adds Android-side network cache management APIs.
