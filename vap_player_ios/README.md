# vap_player_ios

The iOS implementation of [`flutter_vap_player`][1].

It wraps QGVAPlayer `1.0.19` with per-player event streams, pause/resume, repeat,
and VAPX resource callbacks. Texture requests fall back to a platform view.

## Usage

This package is [endorsed][2], which means you can simply use `flutter_vap_player`
normally. This package will be automatically included in your app when you do,
so you do not need to add it to your `pubspec.yaml`.

However, if you `import` this package to use any of its APIs directly, you
should add it to your `pubspec.yaml` as usual.

[1]: https://pub.dev/packages/flutter_vap_player
[2]: https://flutter.dev/to/endorsed-federated-plugin
