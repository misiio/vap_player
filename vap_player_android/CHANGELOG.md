## Unreleased

- Publish the decoder-derived fallback config for VAP v1 files and leave final
  scaling to the app-facing Flutter layout in both rendering modes.
- Check for an already-published config before locking, so steady-state
  playback does not synchronize on the render thread for every frame.

## 2.0.0

- Breaking: adopt the per-player platform contract with explicit creation,
  playback, control, rendering, event, and disposal APIs.
- Add Dart plugin registration and native rendering through Flutter textures
  or platform views while retaining the `app.misi.vap_player_android`
  namespace.
- Add repeat-count, mute, scale, FPS, config/frame/error event, and VAPX
  text/image resource support.
- Report pause and resume as unsupported because the Android VAP renderer
  cannot pause playback.

## 1.0.0

- Breaking: implement the v2 platform contract with play-scoped options and a single event callback.
- Breaking: remove separate host calls for mute, content mode, frame events, and manual cache pruning.

## 0.2.0

- Add hardened Android network download pipeline: strict `2xx` status validation, redirect cap (`3`), bounded transfer size, and MP4 signature validation before caching.
- Add stable network failure error codes (`1001..1005`) for invalid URL, HTTP status, size exceeded, invalid media, and network I/O.
- Align playback event emission with the platform interface `started` event contract.
- Align text resource fallback behavior with iOS and add dedicated fallback coverage tests.
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
