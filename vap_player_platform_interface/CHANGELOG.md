## Unreleased

- Clarify that platform renderers fill their assigned box while the app-facing
  player applies the requested scale consistently across view types.

## 2.0.0

- Breaking: replace the global event stream and view-oriented playback API
  with per-player creation, playback, control, rendering, event, and disposal
  interfaces.
- Breaking: remove the native network-cache contract; sources are now resolved
  to local files by the app-facing package.
- Add sealed `VapEvent` types, player creation/play/view options, view and
  scale types, and VAPX text/image resource delegates.

## 1.0.0

- Breaking: reduce the platform interface to one event stream, one play request, stop/dispose, resolver registration, and compact network cache calls.
- Breaking: collapse Pigeon playback and click callbacks into one `VapEventMessage`.
- Breaking: remove separate mute, content-mode, frame-event, and manual prune host calls.

## 0.2.0

- Rename `VapPlaybackEventType.start` to `VapPlaybackEventType.started` to match emitted playback events.
- Document stable network failure error-code mapping (`1001..1005`) used by platform implementations for `VapPlaybackEvent.errorCode`.

## 0.1.0

- Initial platform interface release for the Flutter VAP federated plugin.
- Defines shared models and method contracts used by app-facing and platform packages.
- Adds generated Pigeon message contracts for Android and iOS implementations.
- Includes resolver behavior and smoke tests for interface stability.
