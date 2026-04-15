# flutter_vap_player
<?code-excerpt path-base="example/lib"?>

[![pub package](https://img.shields.io/pub/v/flutter_vap_player.svg)](https://pub.dev/packages/flutter_vap_player)

A federated Flutter plugin for [Tencent VAP](https://github.com/Tencent/vap) on Android and iOS.

|             | Android | iOS     |
|-------------|---------|---------|
| **Support** | SDK 24+ | iOS 13+ |

## Features

- `VapView` widget for embedding native VAP rendering views.
- `VapController` for `play`, `stop`, `mute`, `contentMode`, and frame-event toggling.
- Source types: `asset`, `file`, and `network` (URL download + cache).
- `VapNetworkCache` global APIs for cache size, clear, and manual prune controls.
- VAPX support:
  - synchronous tag/text replacement from `tagValues`
  - async image resolution from Dart via `setImageResolver`
- Playback + click + error events.

## Package Layout

- `flutter_vap_player` (app-facing API)
- `vap_player_platform_interface` (shared models + pigeon contracts)
- `vap_player_android` (Android implementation, depends on `io.github.tencent:vap:2.0.28`)
- `vap_player_ios` (iOS implementation, depends on `QGVAPlayer` `1.0.19`)

## Quick Use

```dart
import 'package:flutter_vap_player/flutter_vap_player.dart';

final controller = VapController();

controller.setImageResolver((request) async {
  // Return image bytes for VAPX image resources.
  return null;
});

await controller.playAsset(
  'assets/vap.mp4',
  repeatCount: -1,
  mute: true,
  contentMode: VapContentMode.aspectFit,
  tagValues: const {
    '[textUser]': 'Alice',
    '[sImg1]': 'demo://avatar',
  },
);

await controller.playNetwork(
  'https://cdn.example.com/vap/demo.mp4',
  repeatCount: 0,
);

final int cacheBytes = await VapNetworkCache.sizeBytes();
final int autoLimitBytes = await VapNetworkCache.autoEvictionMaxBytes();
await VapNetworkCache.setAutoEvictionMaxBytes(200 * 1024 * 1024);
await VapNetworkCache.pruneToBytes(100 * 1024 * 1024);
await VapNetworkCache.clear();
```

```dart
VapView(controller: controller)
```

## iOS Pod Note

If your environment cannot resolve `QGVAPlayer` from default CocoaPods sources, add an explicit source/override in your app Podfile, for example using the official repo/tag.

## Example

See `flutter_vap_player/example` for complete asset playback and VAPX demo flows.

## Notes

- `VapSourceType.network` treats `source` as an absolute `http/https` URL.
- For network sources, `assetPackage` is ignored.
- Native network cache auto-evicts oldest files after successful downloads when cache size exceeds the configured limit (default `100 MiB`).
