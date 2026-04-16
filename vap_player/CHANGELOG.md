## Unreleased

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
