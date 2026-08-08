import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

/// The type of Flutter view used to render the VAP animation.
enum VapViewType {
  /// Renders into a Flutter [Texture].
  ///
  /// Supported on Android only. On iOS this falls back to [platformView]
  /// because the native VAP renderer draws directly into an on-screen
  /// CAMetalLayer.
  textureView,

  /// Renders with a native platform view.
  platformView,
}

/// How the animation is scaled inside its view.
///
/// In [VapViewType.platformView] mode the scaling is applied by the native
/// view; in texture mode it is applied by Flutter layout around the
/// [Texture] widget.
enum VapScaleType {
  /// Stretch to fill the view (Android FIT_XY / iOS ScaleToFill).
  fitXY,

  /// Scale to fit inside the view, preserving aspect ratio
  /// (Android FIT_CENTER / iOS AspectFit).
  fitCenter,

  /// Scale to fill the view, preserving aspect ratio and cropping
  /// (Android CENTER_CROP / iOS AspectFill).
  centerCrop,
}

/// Options used when creating a player.
@immutable
class VapCreationOptions {
  /// Creates creation options.
  const VapCreationOptions({
    this.viewType = VapViewType.platformView,
    this.enableFrameEvents = false,
  });

  /// The requested view type.
  final VapViewType viewType;

  /// Whether per-frame [VapFrameEvent]s are emitted during playback.
  ///
  /// Defaults to false because at typical VAP frame rates (~25fps) the
  /// events generate significant platform-channel traffic.
  final bool enableFrameEvents;
}

/// Options for a single playback run.
@immutable
class VapPlayOptions {
  /// Creates play options.
  const VapPlayOptions({
    required this.path,
    this.repeatCount = 0,
    this.mute = false,
    this.scaleType = VapScaleType.fitXY,
    this.fps,
    this.enableOldVersion = false,
  });

  /// Local file path of the VAP mp4 to play.
  final String path;

  /// Number of additional plays: 0 plays once, n plays n+1 times,
  /// -1 loops forever.
  final int repeatCount;

  /// Whether the mp4's audio track is muted.
  final bool mute;

  /// Scale mode, effective in platform-view mode only.
  final VapScaleType scaleType;

  /// Optional fps override (Android only; ignored on iOS).
  final int? fps;

  /// Enables playback of VAP v1 mp4s that lack a `vapc` box.
  ///
  /// When false, attempting to play such a file reports a [VapErrorEvent]
  /// with error code 10005 asynchronously rather than throwing from play.
  final bool enableOldVersion;
}

/// Options passed to [VapPlayerPlatform.buildViewWithOptions].
@immutable
class VapViewOptions {
  /// Creates view options for the given player.
  const VapViewOptions({
    required this.playerId,
    this.scaleType = VapScaleType.fitXY,
    this.size,
  });

  /// The player to render.
  final int playerId;

  /// How the animation is fitted into the view.
  ///
  /// Implementations that render into a Flutter [Texture] apply this with
  /// Flutter layout; platform-view implementations apply it natively and
  /// may ignore this field.
  final VapScaleType scaleType;

  /// The animation's display size, or null (or [Size.zero]) while the vapc
  /// config has not been parsed yet.
  ///
  /// Required for texture implementations to apply [VapScaleType.fitCenter]
  /// and [VapScaleType.centerCrop]; without it the animation fills the
  /// view.
  final Size? size;
}
