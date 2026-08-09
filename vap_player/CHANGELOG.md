## Unreleased

## 2.0.0

- Breaking: replace `VapController` and play-scoped sources/options with
  source-bound `VapPlayerController` constructors, explicit `initialize()`,
  parameterless `play()`, and a per-player lifecycle.
- Breaking: expose playback through `VapPlayerValue` state and resource-click
  callbacks, and replace Flutter `BoxFit` configuration with `VapScaleType`.
- Breaking: remove `VapNetworkCache`; asset and network sources are now
  materialized to a Dart-managed local cache before native playback, with
  support for network request headers.
- Add selectable platform-view and texture rendering. Android supports both
  modes; iOS falls back to a platform view for texture requests.
- Add repeat-count and mute controls, detailed config/frame/error state, iOS
  pause/resume, and VAPX text/image resource delegates.

## 1.0.0

- Breaking: replace `VapView` with `VapPlayer`.
- Breaking: replace `playAsset`, `playFile`, and `playNetwork` with one `play(VapSource, options:)` entrypoint.
- Breaking: replace mutable playback setters and separate playback/click streams with play-scoped `VapPlaybackOptions` and one `events` stream.
- Breaking: replace `VapContentMode`/`contentMode` with Flutter `BoxFit` via `VapPlaybackOptions.fit`.
- Breaking: replace the network cache API with `info`, `setMaxBytes`, and `clear`.

## 0.2.0

- Add `VapController.pause()` and `VapController.resume()` playback controls.
- Support safe `VapView` controller handoff at runtime and cancel pending play requests on controller detach.
- Harden controller/view teardown with idempotent disposal and tolerant native view cleanup.
- Align iOS/Android resource fallback behavior and FPS request contract.
- Harden network playback path on Android and iOS with strict HTTP validation (`2xx`), redirect limits (`3`), bounded downloads, and MP4 signature checks before cache promotion.
- Document stable network playback failure codes surfaced through `VapPlaybackEvent.errorCode`.
- Clarify `VapNetworkCache.setAutoEvictionMaxBytes` now governs both cache eviction target and max single network download size (with a `10 MiB` floor).

## 0.1.0

- Initial public release of the federated Flutter VAP plugin.
- Provides `VapView` and `VapController` APIs for Android and iOS playback.
- Supports asset, file, and network VAP sources.
- Adds VAPX tag replacement and async image resolver support.
- Adds playback, click, and error event streams.
- Adds network cache APIs (`VapNetworkCache`) for size, clear, and pruning control.
