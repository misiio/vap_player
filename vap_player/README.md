# flutter_vap_player
<?code-excerpt path-base="example/lib"?>

[![pub package](https://img.shields.io/pub/v/flutter_vap_player.svg)](https://pub.dev/packages/flutter_vap_player)

A federated Flutter plugin for [Tencent VAP](https://github.com/Tencent/vap) on Android and iOS.

|             | Android | iOS     |
|-------------|---------|---------|
| **Support** | SDK 24+ | iOS 13+ |

## Features

- `VapPlayer` widget for embedding native VAP rendering views.
- `VapController` for `play`, `stop`, `dispose`, and a single event stream.
- Source types: `asset`, `file`, and `network` (URL download + cache).
- `VapNetworkCache` global APIs for cache info, clear, and max-size controls.
- VAPX support:
  - synchronous tag/text replacement from play-scoped `tags`
  - async image resolution from play-scoped `imageResolver`
- Playback + click + error events.

## Package Layout

- `flutter_vap_player` (app-facing API)
- `vap_player_platform_interface` (shared models + pigeon contracts)
- `vap_player_android` (Android implementation, depends on `io.github.tencent:vap:2.0.28`)
- `vap_player_ios` (iOS implementation, depends on `QGVAPlayer` `1.0.19`)

## Quick Use

Build `VapPlayer`, then start playback. Calls to `play()` made before the native view is attached are queued automatically.

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
    _controller = VapController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _controller.play(
          VapSource.network(Uri.parse('https://cdn.example.com/vap/demo.mp4')),
          options: VapPlaybackOptions(
            loop: true,
            fit: BoxFit.contain,
            imageResolver: (request) async {
              // Return image bytes for VAPX image resources.
              return null;
            },
          ),
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
    return VapPlayer(controller: _controller);
  }
}
```

```dart
final VapNetworkCacheInfo cache = await VapNetworkCache.info();
// Controls both cache auto-eviction and max single network download size.
await VapNetworkCache.setMaxBytes(200 * 1024 * 1024);
await VapNetworkCache.clear();
```

## iOS Pod Note

If your environment cannot resolve `QGVAPlayer` from default CocoaPods sources, add an explicit source/override in your app Podfile, for example using the official repo/tag.

## Example

See `flutter_vap_player/example` for complete asset playback and VAPX demo flows.

## Notes

- `VapSource.network` requires an absolute `http/https` URL.
- For network sources, asset package values are ignored.
- Missing `tags` entries fall back to the original tag string on both Android and iOS.
- `VapImageResolveRequest.resourceId` is platform-specific: Android forwards native `srcId`, while iOS falls back to the tag value when native `srcId` is unavailable in `QGVAPSourceInfo`.
- Native network downloads are hardened with strict `2xx` checks, redirect limits (`3`), size caps, and MP4 signature validation before cache promotion.
- `VapNetworkCache.setMaxBytes()` controls both:
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
