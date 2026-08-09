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
/// Platform implementations always render the animation filling whatever box
/// they are given; the fit itself is applied by the app-facing player widget,
/// so that it behaves identically across platforms and view types.
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

  /// The requested scale mode.
  ///
  /// Implementations normalize their native renderer to fill and leave the fit
  /// to the app-facing player widget, so this is carried for completeness
  /// rather than acted on.
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
  /// Implementations return a renderer that fills the box it is given; the
  /// caller applies the fit around it. This is passed for implementations that
  /// need to know what they are being sized for.
  final VapScaleType scaleType;

  /// The animation's display size, or null (or [Size.zero]) while it is not
  /// known yet.
  ///
  /// Like [scaleType], this describes the fit the caller is applying rather
  /// than something the implementation acts on.
  final Size? size;
}
