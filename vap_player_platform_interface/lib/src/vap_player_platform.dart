import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'vap_events.dart';
import 'vap_resource.dart';
import 'vap_types.dart';

/// The interface that implementations of vap_player must implement.
///
/// Platform implementations should extend this class rather than implement
/// it, so that new methods added here are not breaking changes.
abstract class VapPlayerPlatform extends PlatformInterface {
  /// Constructs a VapPlayerPlatform.
  VapPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VapPlayerPlatform _instance = _PlaceholderImplementation();

  /// The instance of [VapPlayerPlatform] to use.
  static VapPlayerPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own
  /// platform-specific class that extends [VapPlayerPlatform] when they
  /// register themselves.
  static set instance(VapPlayerPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Initializes the platform implementation, clearing any existing players.
  Future<void> init() {
    throw UnimplementedError('init() has not been implemented.');
  }

  /// Creates a player and returns its id.
  Future<int> create(VapCreationOptions options) {
    throw UnimplementedError('create() has not been implemented.');
  }

  /// Disposes of the player and its resources.
  Future<void> dispose(int playerId) {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  /// Starts playing the mp4 at `options.path` from the first frame.
  ///
  /// VAP has no prepare/seek step: calling this always (re)starts playback.
  Future<void> play(int playerId, VapPlayOptions options) {
    throw UnimplementedError('play() has not been implemented.');
  }

  /// Stops playback.
  Future<void> stop(int playerId) {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// Pauses playback.
  ///
  /// Only supported when [isPauseResumeSupported] is true (iOS); the
  /// Android VAP library cannot pause and throws [UnsupportedError].
  Future<void> pause(int playerId) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// Resumes playback after [pause].
  ///
  /// Only supported when [isPauseResumeSupported] is true (iOS).
  Future<void> resume(int playerId) {
    throw UnimplementedError('resume() has not been implemented.');
  }

  /// Whether [pause] and [resume] are supported on this platform.
  bool get isPauseResumeSupported => false;

  /// Mutes or unmutes the animation's audio track.
  ///
  /// On iOS this only takes effect at the start of the next play/loop.
  Future<void> setMute(int playerId, bool mute) {
    throw UnimplementedError('setMute() has not been implemented.');
  }

  /// Sets the repeat count for subsequent plays:
  /// 0 plays once, n plays n+1 times, -1 loops forever.
  Future<void> setRepeatCount(int playerId, int repeatCount) {
    throw UnimplementedError('setRepeatCount() has not been implemented.');
  }

  /// Registers (or clears, with null) the VAPX resource delegate consulted
  /// during playback of mix animations. Must be set before [play].
  void setResourceDelegate(int playerId, VapResourceDelegate? delegate) {
    throw UnimplementedError('setResourceDelegate() has not been implemented.');
  }

  /// Returns a stream of events for the given player.
  Stream<VapEvent> vapEventsFor(int playerId) {
    throw UnimplementedError('vapEventsFor() has not been implemented.');
  }

  /// Returns a widget displaying the video.
  Widget buildViewWithOptions(VapViewOptions options) {
    throw UnimplementedError(
      'buildViewWithOptions() has not been implemented.',
    );
  }
}

class _PlaceholderImplementation extends VapPlayerPlatform {}
