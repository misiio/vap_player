## Unreleased

- Leave final scaling to the app-facing Flutter layout instead of the nil vapc
  model, which cannot describe a VAP v1 file.
- Drop the per-frame legacy config callback: the app-facing package now reads
  those dimensions from the mp4 before playback starts.

## 2.0.0

- Breaking: adopt the per-player platform contract with explicit creation,
  playback, control, rendering, event, and disposal APIs.
- Add Swift Package Manager support while retaining CocoaPods compatibility.
- Use QGVAPlayer `1.0.19` with CocoaPods and pin SPM builds to
  `misiio/vap` `1.0.19-spm`.
- Add native per-player QGVA rendering with pause/resume, repeat, mute, scale,
  config/frame/error events, and VAPX text/image resources.
- Fall back to a platform view when texture rendering is requested because
  QGVAPlayer renders directly to an on-screen Metal layer.
- Report VAP old-version parse failures as error `10005` before native cleanup.

## 1.0.0

- Breaking: implement the v2 platform contract with play-scoped options and a single event callback.
- Breaking: remove separate host calls for mute, content mode, frame events, and manual cache pruning.

## 0.2.1

- Add iOS 13.0 compatibility fallback for ISO BMFF signature reads by using `readData(ofLength:)` when `read(upToCount:)` is unavailable.
- Fix example iOS build configuration by forcing `FLUTTER_APPLICATION_PATH` to resolve from `$(SRCROOT)/..` in xcconfig overrides.

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
