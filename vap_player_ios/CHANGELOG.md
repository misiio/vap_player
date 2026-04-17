## Unreleased

## 0.2.0

- Add hardened iOS network download pipeline using bounded `URLSession` download delegates with strict `2xx` validation, redirect cap (`3`), and max-size enforcement.
- Validate MP4 signature before promoting downloaded files into cache.
- Standardize network failure error codes (`1001..1005`) and sanitize URL text in failure messages.
- Align playback event emission with the platform interface `started` event contract.
- Align text resource fallback behavior with Android and document FPS requests as hints in wrap-view playback APIs.

## 0.1.0

- Initial iOS federated implementation release for `flutter_vap_player`.
- Implements platform view rendering and playback controls.
- Supports asset, file, and network playback requests.
- Supports VAPX text/tag replacement and async image resource loading.
- Adds iOS-side network cache management APIs.
