# vap_player

Federated Flutter plugin for [Tencent VAP](https://github.com/Tencent/vap) on Android and iOS.

## Features

- `VapView` widget for embedding native VAP rendering views.
- `VapController` for `play`, `stop`, `mute`, `contentMode`, and frame-event toggling.
- VAPX support:
  - synchronous tag/text replacement from `tagValues`
  - async image resolution from Dart via `setImageResolver`
- Playback + click + error events.

## Package Layout

- `vap_player` (app-facing API)
- `vap_player_platform_interface` (shared models + pigeon contracts)
- `vap_player_android` (Android implementation, depends on `io.github.tencent:vap:2.0.28`)
- `vap_player_ios` (iOS implementation, depends on `QGVAPlayer` `1.0.19`)

## Quick Use

```dart
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
```

```dart
VapView(controller: controller)
```

## iOS Pod Note

If your environment cannot resolve `QGVAPlayer` from default CocoaPods sources, add an explicit source/override in your app Podfile, for example using the official repo/tag.

## Example

See `vap_player/example` for complete asset playback and VAPX demo flows.
