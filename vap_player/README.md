# flutter_vap_player

A federated Flutter plugin for playing [Tencent VAP](https://github.com/Tencent/vap)
(Video Animation Player) alpha-video animations on **Android** and **iOS**,
including **VAPX** (mix/fusion) dynamic text and image injection.

## Packages

| Package | Role |
| --- | --- |
| [`flutter_vap_player`](./) | App-facing API (`VapPlayerController`, `VapPlayer` widget) |
| [`vap_player_platform_interface`](../vap_player_platform_interface/) | Shared platform interface |
| [`vap_player_android`](../vap_player_android/) | Android implementation (`io.github.tencent:vap:2.0.28`) |
| [`vap_player_ios`](../vap_player_ios/) | iOS implementation (CocoaPods `QGVAPlayer`) |

Platform communication uses [pigeon](https://pub.dev/packages/pigeon)
(`@HostApi` for commands, `@FlutterApi` for VAPX resource callbacks, and
`@EventChannelApi` for per-player event streams).

## Rendering modes

| | `VapViewType.textureView` | `VapViewType.platformView` |
| --- | --- | --- |
| Android | ✅ Flutter `Texture` (headless `IAnimView` feeding a `SurfaceTexture`) | ✅ native `AnimView` |
| iOS | ⚠️ falls back to platform view | ✅ native `QGVAPWrapView` |

The iOS VAP renderer draws directly into an on-screen `CAMetalLayer`, so a
true Flutter texture is not possible there without forking the renderer;
requesting `textureView` on iOS silently uses a platform view instead.

## Usage

```dart
import 'package:flutter_vap_player/flutter_vap_player.dart';

final controller = VapPlayerController.asset(
  'assets/vap/demo.mp4',
  options: const VapPlayerOptions(
    viewType: VapViewType.textureView, // Android texture; iOS platform view
    repeatCount: 0,                    // 0 = once, n = n+1 plays, -1 = loop
    scaleType: VapScaleType.fitCenter, // platform-view mode only
  ),
);
await controller.initialize();
// ...
VapPlayer(controller) // in your widget tree
// ...
await controller.play();
```

Sources: `VapPlayerController.asset`, `.file`, and `.networkUrl` (assets and
network URLs are materialized to a local cache file first — the native VAP
libraries only play local files).

### VAPX (mix resources)

```dart
VapPlayerOptions(
  resourceDelegate: VapResourceDelegate(
    resolveText: (resource) async => 'text for ${resource.tag}',
    resolveImage: (resource) async => await loadPngBytes(resource.tag),
  ),
  onResourceClick: (resource) => print('tapped ${resource.tag}'),
)
```

`resolveImage` returns encoded PNG/JPEG bytes; decoding happens natively.
Native code applies a 5-second timeout per resource — a slow or missing
delegate leaves the slot empty instead of blocking playback forever.

## Platform notes

- **No pause/seek on Android**: the VAP Android library only supports
  start/stop/loop. `pause()`/`resume()` work on iOS (`value.canPause`),
  and throw `UnsupportedError` on Android.
- `play()` always restarts from the first frame (VAP has no prepare/seek
  step); animation metadata (`value.size`, `frameCount`, …) becomes
  available shortly after `play()` via the config-ready event.
- Per-frame progress events are opt-in
  (`VapPlayerOptions.enableFrameEvents`) to limit channel traffic.
- Resource-click events require platform-view mode (touches are handled by
  the native view).
- iOS mute changes apply at the next play/loop start.
- The iOS simulator does not render VAP animations (Metal is stubbed out);
  test on a real device.

## Example

`example` demonstrates all three modes: Texture, PlatformView
with scale-type switching, and VAPX with dynamic text/images (demo assets
from the Tencent VAP repository).

## Development

```sh
# Regenerate pigeon bindings after editing pigeons/messages.dart:
cd vap_player_android && dart run pigeon --input pigeons/messages.dart
cd vap_player_ios && dart run pigeon --input pigeons/messages.dart

# Run tests:
cd vap_player && flutter test
cd vap_player_android && flutter test
cd vap_player_ios && flutter test

# Build the example:
cd vap_player/example
flutter build apk --debug
flutter build ios --no-codesign --debug
```
