import 'vap_resource.dart';

/// An event emitted by a native VAP player.
sealed class VapEvent {
  const VapEvent();
}

/// The animation's vapc configuration was parsed; playback is about to start.
class VapConfigReadyEvent extends VapEvent {
  /// Creates a config-ready event.
  const VapConfigReadyEvent({
    required this.width,
    required this.height,
    required this.videoWidth,
    required this.videoHeight,
    required this.frameCount,
    required this.fps,
    required this.isMix,
  });

  /// Intended display width of the animation, in pixels.
  final int width;

  /// Intended display height of the animation, in pixels.
  final int height;

  /// Width of the underlying mp4 video, in pixels.
  final int videoWidth;

  /// Height of the underlying mp4 video, in pixels.
  final int videoHeight;

  /// Total number of frames.
  final int frameCount;

  /// Frames per second.
  final int fps;

  /// Whether the animation contains VAPX mix resources.
  final bool isMix;
}

/// Playback started (first frame rendered).
class VapStartedEvent extends VapEvent {
  /// Creates a started event.
  const VapStartedEvent();
}

/// A frame was rendered. Only emitted when
/// `VapCreationOptions.enableFrameEvents` is true.
class VapFrameEvent extends VapEvent {
  /// Creates a frame event.
  const VapFrameEvent(this.frameIndex);

  /// Index of the rendered frame.
  final int frameIndex;
}

/// Playback finished (all repeats completed, or stopped).
class VapCompletedEvent extends VapEvent {
  /// Creates a completed event.
  const VapCompletedEvent();
}

/// The native player released its resources.
class VapDestroyedEvent extends VapEvent {
  /// Creates a destroyed event.
  const VapDestroyedEvent();
}

/// Playback failed.
class VapErrorEvent extends VapEvent {
  /// Creates an error event.
  const VapErrorEvent({required this.code, this.message});

  /// Native error code (see VAP's Constant.REPORT_ERROR_TYPE_*).
  final int code;

  /// Human-readable error message, if any.
  final String? message;
}

/// A VAPX resource was tapped.
class VapResourceClickEvent extends VapEvent {
  /// Creates a resource-click event.
  const VapResourceClickEvent(this.resource);

  /// The tapped resource.
  final VapResource resource;
}
