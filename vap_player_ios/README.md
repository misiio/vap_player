# vap_player_ios

The iOS implementation of [`flutter_vap_player`][1].

It wraps QGVAPlayer with per-player event streams, pause/resume, repeat, and
VAPX resource callbacks. CocoaPods uses QGVAPlayer `1.0.19`; Swift Package
Manager uses the compatible `1.0.19-spm` release from
[`misiio/vap`](https://github.com/misiio/vap). Texture requests fall back to a
platform view.

## Usage

This package is [endorsed][2], which means you can simply use `flutter_vap_player`
normally. This package will be automatically included in your app when you do,
so you do not need to add it to your `pubspec.yaml`.

However, if you `import` this package to use any of its APIs directly, you
should add it to your `pubspec.yaml` as usual.

## iOS dependency managers

The plugin supports both CocoaPods and Flutter's Swift Package Manager
integration. Existing CocoaPods apps continue to use the podspec. For SPM,
enable Flutter's integration in the consuming app:

```sh
flutter config --enable-swift-package-manager
```

Flutter then discovers the bundled `vap-player-ios` product automatically; no
manual Xcode package entry is required.

[1]: https://pub.dev/packages/flutter_vap_player
[2]: https://flutter.dev/to/endorsed-federated-plugin
