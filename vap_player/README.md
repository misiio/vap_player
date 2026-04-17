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

Build `VapView` first, then start playback. Do not block mounting with `await controller.play*()` before the view exists.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_vap_player/flutter_vap_player.dart';

class VapSamplePage extends StatefulWidget {
  const VapSamplePage({super.key});

  @override
  State<VapSamplePage> createState() => _VapSamplePageState();
}

class _VapSamplePageState extends State<VapSamplePage> {
  late final VapController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VapController(autoPlay: true, looping: true);

    _controller.setImageResolver((request) async {
      // Return image bytes for VAPX image resources.
      return null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _controller.playNetwork(
          'https://cdn.example.com/vap/demo.mp4',
          repeatCount: 0,
          contentMode: VapContentMode.aspectFit,
        ).catchError((Object error, StackTrace stackTrace) {
          debugPrint('Failed to start VAP playback: $error');
          debugPrintStack(stackTrace: stackTrace);
        }),
      );
    });
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VapView(controller: _controller);
  }
}
```

```dart
final int cacheBytes = await VapNetworkCache.sizeBytes();
final int autoLimitBytes = await VapNetworkCache.autoEvictionMaxBytes();
// Controls both cache auto-eviction and max single network download size.
await VapNetworkCache.setAutoEvictionMaxBytes(200 * 1024 * 1024);
await VapNetworkCache.pruneToBytes(100 * 1024 * 1024);
await VapNetworkCache.clear();
```

## iOS Pod Note

If your environment cannot resolve `QGVAPlayer` from default CocoaPods sources, add an explicit source/override in your app Podfile, for example using the official repo/tag.

## Example

See `flutter_vap_player/example` for complete asset playback and VAPX demo flows.

## Notes

- `VapSourceType.network` treats `source` as an absolute `http/https` URL.
- For network sources, `assetPackage` is ignored.
- Missing `tagValues` entries fall back to the original tag string on both Android and iOS.
- `VapImageResolveRequest.resourceId` is platform-specific: Android forwards native `srcId`, while iOS falls back to the tag value when native `srcId` is unavailable in `QGVAPSourceInfo`.
- `fps` in play requests is currently effective on Android. iOS uses `QGVAPWrapView` APIs (which do not expose fps override), so `fps` is treated as a best-effort hint and currently ignored.
- Native network downloads are hardened with strict `2xx` checks, redirect limits (`3`), size caps, and MP4 signature validation before cache promotion.
- `VapNetworkCache.setAutoEvictionMaxBytes()` controls both:
  1. cache auto-eviction target
  2. maximum allowed size of a single network download (minimum enforced floor: `10 MiB`)
- Native network cache auto-evicts oldest files after successful downloads when cache size exceeds the configured limit (default `100 MiB`).

### Network Failure Error Codes (`VapPlaybackEvent.errorCode`)

| Code | Meaning |
|------|---------|
| `1001` | invalid URL / unsupported scheme |
| `1002` | HTTP status validation failed |
| `1003` | response exceeded max download size |
| `1004` | invalid media (missing/invalid MP4 `ftyp` signature) |
| `1005` | network I/O failure (including redirect overflow) |
