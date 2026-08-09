import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

import 'source_cache.dart';
import 'vap_metadata.dart';

VapPlayerPlatform get _platform => VapPlayerPlatform.instance;

/// A player id that indicates the controller has not been initialized.
const int kUninitializedPlayerId = -1;

/// The kind of data source a [VapPlayerController] plays.
enum VapDataSourceType {
  /// A Flutter asset bundled with the app.
  asset,

  /// A file on the local device.
  file,

  /// A network URL, downloaded to a local cache file before playback.
  network,
}

/// Static configuration for a [VapPlayerController].
@immutable
class VapPlayerOptions {
  /// Creates controller options.
  const VapPlayerOptions({
    this.viewType = VapViewType.platformView,
    int? repeatCount,
    bool? loop,
    this.mute = false,
    this.scaleType = VapScaleType.fitXY,
    this.fps,
    this.enableOldVersion = false,
    this.enableFrameEvents = false,
    this.resourceDelegate,
    this.onResourceClick,
  }) : repeatCount = repeatCount ?? (loop == null ? 0 : (loop ? -1 : 0));

  /// The requested view type. On iOS, [VapViewType.textureView] falls back
  /// to a platform view.
  final VapViewType viewType;

  /// Initial repeat count: 0 plays once, n plays n+1 times, -1 loops
  /// forever. Can be changed later with
  /// [VapPlayerController.setRepeatCount].
  ///
  /// `loop` is a convenience alias: `true` maps to -1, `false` maps to 0.
  /// If both [repeatCount] and `loop` are passed, [repeatCount] takes
  /// precedence and `loop` is ignored.
  final int repeatCount;

  /// Whether the audio track starts muted.
  final bool mute;

  /// How the animation is fitted into the [VapPlayer] widget. Applied by a
  /// stable Flutter layout around both texture and platform-view renderers.
  final VapScaleType scaleType;

  /// Optional fps override (Android only).
  final int? fps;

  /// Enables VAP v1 mp4s that lack a `vapc` box.
  ///
  /// When false, attempting to play such a file reports a [VapErrorEvent]
  /// with error code 10005 asynchronously; [VapPlayerController.play] does
  /// not throw for this native playback failure.
  final bool enableOldVersion;

  /// Whether per-frame [VapFrameEvent]s are delivered (updates
  /// [VapPlayerValue.currentFrame] continuously). Off by default to limit
  /// platform-channel traffic.
  final bool enableFrameEvents;

  /// Supplies VAPX mix resources (text and images) during playback.
  final VapResourceDelegate? resourceDelegate;

  /// Called when a VAPX resource is tapped (platform-view mode only).
  final void Function(VapResource resource)? onResourceClick;
}

/// The playback state of a [VapPlayerController].
@immutable
class VapPlayerValue {
  /// Creates a player value.
  const VapPlayerValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isCompleted = false,
    this.size = Size.zero,
    this.videoSize = Size.zero,
    this.frameCount = 0,
    this.fps = 0,
    this.isMix = false,
    this.currentFrame = 0,
    this.canPause = false,
    this.errorDescription,
  });

  /// True after [VapPlayerController.initialize] completes.
  final bool isInitialized;

  /// True while an animation is playing.
  final bool isPlaying;

  /// True once playback has finished (all repeats done or stopped).
  final bool isCompleted;

  /// Intended display size of the animation. Read from the mp4 by
  /// [VapPlayerController.initialize], and refined by the platform once it
  /// has parsed the file.
  final Size size;

  /// Size of the underlying mp4 video.
  final Size videoSize;

  /// Total number of frames, or 0 when the file does not declare one (VAP v1
  /// files only report it once playback has started).
  final int frameCount;

  /// Frames per second, or 0 when the file does not declare one (VAP v1
  /// files only report it once playback has started).
  final int fps;

  /// Whether the animation declares VAPX mix resources.
  final bool isMix;

  /// The most recently rendered frame index. Only updated when
  /// [VapPlayerOptions.enableFrameEvents] is set.
  final int currentFrame;

  /// Whether pause/resume are supported (iOS only).
  final bool canPause;

  /// A description of the last playback error, or null.
  final String? errorDescription;

  /// True if playback has failed.
  bool get hasError => errorDescription != null;

  /// The display aspect ratio, or 1 when unknown.
  double get aspectRatio {
    if (!size.isEmpty && size.width > 0 && size.height > 0) {
      return size.width / size.height;
    }
    return 1;
  }

  /// Returns a copy with the given fields replaced.
  VapPlayerValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isCompleted,
    Size? size,
    Size? videoSize,
    int? frameCount,
    int? fps,
    bool? isMix,
    int? currentFrame,
    bool? canPause,
    String? errorDescription = _defaultErrorDescription,
  }) {
    return VapPlayerValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isCompleted: isCompleted ?? this.isCompleted,
      size: size ?? this.size,
      videoSize: videoSize ?? this.videoSize,
      frameCount: frameCount ?? this.frameCount,
      fps: fps ?? this.fps,
      isMix: isMix ?? this.isMix,
      currentFrame: currentFrame ?? this.currentFrame,
      canPause: canPause ?? this.canPause,
      errorDescription: identical(errorDescription, _defaultErrorDescription)
          ? this.errorDescription
          : errorDescription,
    );
  }

  static const String _defaultErrorDescription = '__defaultError__';

  @override
  String toString() =>
      'VapPlayerValue(isInitialized: $isInitialized, isPlaying: $isPlaying, '
      'isCompleted: $isCompleted, size: $size, frameCount: $frameCount, '
      'fps: $fps, isMix: $isMix, currentFrame: $currentFrame, '
      'errorDescription: $errorDescription)';
}

/// Controls a native VAP player and publishes its state.
///
/// Unlike video_player there is no prepare/seek step: [play] always starts
/// the animation from the first frame. The animation's size is read from the
/// mp4 during [initialize], so [VapPlayerValue.size] is usable for layout
/// before playback begins.
class VapPlayerController extends ValueNotifier<VapPlayerValue> {
  /// Plays a VAP mp4 bundled as a Flutter asset.
  VapPlayerController.asset(
    this.dataSource, {
    this.package,
    VapPlayerOptions? options,
  }) : dataSourceType = VapDataSourceType.asset,
       httpHeaders = null,
       options = options ?? const VapPlayerOptions(),
       super(const VapPlayerValue());

  /// Plays a VAP mp4 from a local [File].
  VapPlayerController.file(File file, {VapPlayerOptions? options})
    : dataSource = file.path,
      dataSourceType = VapDataSourceType.file,
      package = null,
      httpHeaders = null,
      options = options ?? const VapPlayerOptions(),
      super(const VapPlayerValue());

  /// Plays a VAP mp4 from a network [url], downloading it to a local
  /// cache file first.
  VapPlayerController.networkUrl(
    Uri url, {
    this.httpHeaders,
    VapPlayerOptions? options,
  }) : dataSource = url.toString(),
       dataSourceType = VapDataSourceType.network,
       package = null,
       options = options ?? const VapPlayerOptions(),
       super(const VapPlayerValue());

  /// The asset name, file path, or URL this controller plays.
  final String dataSource;

  /// The kind of data source.
  final VapDataSourceType dataSourceType;

  /// The asset package for [VapPlayerController.asset] sources.
  final String? package;

  /// HTTP headers for [VapPlayerController.networkUrl] sources.
  final Map<String, String>? httpHeaders;

  /// Static configuration for this controller.
  final VapPlayerOptions options;

  int _playerId = kUninitializedPlayerId;
  String? _localPath;
  final StreamController<VapEvent> _eventsController =
      StreamController<VapEvent>.broadcast();
  StreamSubscription<VapEvent>? _eventSubscription;
  bool _isDisposed = false;

  /// The platform player id, or [kUninitializedPlayerId] before
  /// [initialize] completes.
  int get playerId => _playerId;

  /// Visible for testing only.
  @visibleForTesting
  set playerId(int playerId) => _playerId = playerId;

  /// Playback and interaction events emitted by this player.
  ///
  /// This is a broadcast stream, does not replay events, and closes when the
  /// controller is disposed. Read [value] for the player's current state.
  Stream<VapEvent> get events => _eventsController.stream;

  /// Creates the native player, resolves the data source to a local file,
  /// reads the animation's size from it, and subscribes to player events.
  ///
  /// This performs real file I/O, so widget tests must call it inside
  /// `tester.runAsync` rather than the FakeAsync test zone.
  Future<void> initialize() async {
    final String localPath = switch (dataSourceType) {
      VapDataSourceType.asset => await SourceCache.materializeAsset(
        package == null ? dataSource : 'packages/$package/$dataSource',
      ),
      VapDataSourceType.file => dataSource,
      VapDataSourceType.network => await SourceCache.materializeNetwork(
        Uri.parse(dataSource),
        httpHeaders: httpHeaders,
      ),
    };
    if (_isDisposed) {
      return;
    }
    _localPath = localPath;

    // Read the animation's dimensions up front so [VapPlayer] can fit it from
    // its first frame. The platform's config-ready event refines this later,
    // and covers files this cannot parse.
    final VapMetadata? metadata = await readVapMetadata(localPath);
    if (_isDisposed) {
      return;
    }

    _playerId = await _platform.create(
      VapCreationOptions(
        viewType: options.viewType,
        enableFrameEvents: options.enableFrameEvents,
      ),
    );
    if (_isDisposed) {
      await _platform.dispose(_playerId);
      return;
    }

    if (options.resourceDelegate != null) {
      _platform.setResourceDelegate(_playerId, options.resourceDelegate);
    }
    _eventSubscription = _platform
        .vapEventsFor(_playerId)
        .listen(_onEvent, onError: _onError);

    value = value.copyWith(
      isInitialized: true,
      canPause: _platform.isPauseResumeSupported,
      size: metadata?.size,
      videoSize: metadata?.videoSize,
      frameCount: metadata?.frameCount,
      fps: metadata?.fps,
      isMix: metadata?.isMix,
    );
  }

  void _onEvent(VapEvent event) {
    if (_isDisposed) {
      return;
    }
    switch (event) {
      case VapConfigReadyEvent():
        value = value.copyWith(
          size: Size(event.width.toDouble(), event.height.toDouble()),
          videoSize: Size(
            event.videoWidth.toDouble(),
            event.videoHeight.toDouble(),
          ),
          frameCount: event.frameCount,
          fps: event.fps,
          isMix: event.isMix,
        );
      case VapStartedEvent():
        value = value.copyWith(
          isPlaying: true,
          isCompleted: false,
          errorDescription: null,
        );
      case VapFrameEvent():
        value = value.copyWith(currentFrame: event.frameIndex);
      case VapCompletedEvent():
        value = value.copyWith(isPlaying: false, isCompleted: true);
      case VapDestroyedEvent():
        value = value.copyWith(isPlaying: false);
      case VapErrorEvent():
        value = value.copyWith(
          isPlaying: false,
          errorDescription:
              event.message ?? 'VAP playback failed (${event.code})',
        );
      case VapResourceClickEvent():
        break;
    }

    // Publish after updating value so event listeners observe matching state.
    _eventsController.add(event);
    if (event case VapResourceClickEvent(:final resource)) {
      options.onResourceClick?.call(resource);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_isDisposed) {
      return;
    }
    value = value.copyWith(errorDescription: error.toString());
    _eventsController.addError(error, stackTrace);
  }

  /// Starts playback from the first frame.
  Future<void> play() async {
    _ensureLive('play');
    await _platform.play(
      _playerId,
      VapPlayOptions(
        path: _localPath!,
        repeatCount: options.repeatCount,
        mute: options.mute,
        scaleType: options.scaleType,
        fps: options.fps,
        enableOldVersion: options.enableOldVersion,
      ),
    );
  }

  /// Stops playback.
  Future<void> stop() async {
    _ensureLive('stop');
    await _platform.stop(_playerId);
  }

  /// Pauses playback. Only supported when [VapPlayerValue.canPause] is
  /// true (iOS); throws [UnsupportedError] otherwise.
  Future<void> pause() async {
    _ensureLive('pause');
    await _platform.pause(_playerId);
  }

  /// Resumes playback after [pause]. iOS only, like [pause].
  Future<void> resume() async {
    _ensureLive('resume');
    await _platform.resume(_playerId);
  }

  /// Mutes or unmutes the audio track. On iOS this takes effect at the
  /// next play/loop start.
  Future<void> setMute(bool mute) async {
    _ensureLive('setMute');
    await _platform.setMute(_playerId, mute);
  }

  /// Sets the repeat count for subsequent plays: 0 plays once, n plays
  /// n+1 times, -1 loops forever.
  Future<void> setRepeatCount(int repeatCount) async {
    _ensureLive('setRepeatCount');
    await _platform.setRepeatCount(_playerId, repeatCount);
  }

  void _ensureLive(String operation) {
    if (_isDisposed) {
      throw StateError('$operation() was called on a disposed controller.');
    }
    if (_playerId == kUninitializedPlayerId) {
      throw StateError(
        '$operation() was called before initialize() completed.',
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    try {
      await _eventSubscription?.cancel();
      if (_playerId != kUninitializedPlayerId) {
        _platform.setResourceDelegate(_playerId, null);
        await _platform.dispose(_playerId);
        _playerId = kUninitializedPlayerId;
      }
    } finally {
      await _eventsController.close();
      super.dispose();
    }
  }
}
