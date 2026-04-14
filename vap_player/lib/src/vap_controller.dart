import 'dart:async';

import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

class VapController {
  VapController({
    this.autoPlay = false,
    bool looping = false,
    VapPlayerPlatform? platform,
  }) : _platform = platform ?? VapPlayerPlatform.instance,
       _looping = looping {
    _playbackSubscription = _platform.playbackEvents.listen((
      VapPlaybackEvent event,
    ) {
      if (_viewId == event.viewId) {
        _playbackEventsController.add(event);
      }
    });
    _clickSubscription = _platform.clickEvents.listen((
      VapResourceClickEvent event,
    ) {
      if (_viewId == event.viewId) {
        _clickEventsController.add(event);
      }
    });
  }

  final VapPlayerPlatform _platform;
  final bool autoPlay;
  bool _looping;

  final StreamController<VapPlaybackEvent> _playbackEventsController =
      StreamController<VapPlaybackEvent>.broadcast();
  final StreamController<VapResourceClickEvent> _clickEventsController =
      StreamController<VapResourceClickEvent>.broadcast();

  late final StreamSubscription<VapPlaybackEvent> _playbackSubscription;
  late final StreamSubscription<VapResourceClickEvent> _clickSubscription;

  int? _viewId;
  VapImageResolver? _imageResolver;
  _PendingPlay? _pendingPlay;
  bool _disposed = false;

  Stream<VapPlaybackEvent> get playbackEvents =>
      _playbackEventsController.stream;

  Stream<VapResourceClickEvent> get clickEvents =>
      _clickEventsController.stream;

  bool get isAttached => _viewId != null;

  int? get viewId => _viewId;
  bool get looping => _looping;

  void attach(int viewId) {
    _assertNotDisposed();
    if (_viewId == viewId) {
      return;
    }
    if (_viewId != null && _viewId != viewId) {
      throw StateError(
        'This VapController is already attached to viewId=$_viewId. '
        'Create a new controller for another VapView.',
      );
    }
    _viewId = viewId;
    _platform.setImageResolver(viewId, _imageResolver);
    _flushPendingPlay(viewId);
  }

  Future<void> onViewDisposed() async {
    _cancelPendingPlay(
      StateError(
        'Pending play request was cancelled because the view was disposed.',
      ),
    );
    final int? currentViewId = _viewId;
    _viewId = null;
    if (currentViewId != null) {
      _platform.setImageResolver(currentViewId, null);
      await _platform.dispose(currentViewId);
    }
  }

  void setImageResolver(VapImageResolver? resolver) {
    _assertNotDisposed();
    _imageResolver = resolver;
    final int? currentViewId = _viewId;
    if (currentViewId != null) {
      _platform.setImageResolver(currentViewId, resolver);
    }
  }

  void setLooping(bool looping) {
    _assertNotDisposed();
    _looping = looping;
  }

  Future<void> play({
    required VapSourceType sourceType,
    required String source,
    String? assetPackage,
    int? repeatCount,
    bool mute = false,
    VapContentMode contentMode = VapContentMode.scaleToFill,
    int? fps,
    bool frameEventsEnabled = false,
    Map<String, String> tagValues = const <String, String>{},
  }) {
    _assertNotDisposed();
    final int effectiveRepeatCount = repeatCount ?? (_looping ? -1 : 0);
    final _PlayParams params = _PlayParams(
      sourceType: sourceType,
      source: source,
      assetPackage: assetPackage,
      repeatCount: effectiveRepeatCount,
      mute: mute,
      contentMode: contentMode,
      fps: fps,
      frameEventsEnabled: frameEventsEnabled,
      tagValues: tagValues,
    );

    final int? currentViewId = _viewId;
    if (currentViewId != null) {
      return _platform.play(_toPlayRequest(currentViewId, params));
    }
    if (!autoPlay) {
      throw StateError('VapController is not attached to a VapView yet.');
    }
    return _queuePendingPlay(params);
  }

  Future<void> playAsset(
    String assetPath, {
    String? assetPackage,
    int? repeatCount,
    bool mute = false,
    VapContentMode contentMode = VapContentMode.scaleToFill,
    int? fps,
    bool frameEventsEnabled = false,
    Map<String, String> tagValues = const <String, String>{},
  }) {
    return play(
      sourceType: VapSourceType.asset,
      source: assetPath,
      assetPackage: assetPackage,
      repeatCount: repeatCount,
      mute: mute,
      contentMode: contentMode,
      fps: fps,
      frameEventsEnabled: frameEventsEnabled,
      tagValues: tagValues,
    );
  }

  Future<void> playFile(
    String filePath, {
    int? repeatCount,
    bool mute = false,
    VapContentMode contentMode = VapContentMode.scaleToFill,
    int? fps,
    bool frameEventsEnabled = false,
    Map<String, String> tagValues = const <String, String>{},
  }) {
    return play(
      sourceType: VapSourceType.file,
      source: filePath,
      repeatCount: repeatCount,
      mute: mute,
      contentMode: contentMode,
      fps: fps,
      frameEventsEnabled: frameEventsEnabled,
      tagValues: tagValues,
    );
  }

  Future<void> playNetwork(
    String url, {
    int? repeatCount,
    bool mute = false,
    VapContentMode contentMode = VapContentMode.scaleToFill,
    int? fps,
    bool frameEventsEnabled = false,
    Map<String, String> tagValues = const <String, String>{},
  }) {
    final Uri? parsed = Uri.tryParse(url);
    final String? scheme = parsed?.scheme.toLowerCase();
    final bool valid =
        parsed != null &&
        parsed.isAbsolute &&
        (scheme == 'http' || scheme == 'https');
    if (!valid) {
      throw StateError(
        'playNetwork requires an absolute http/https URL. Received: $url',
      );
    }
    return play(
      sourceType: VapSourceType.network,
      source: url,
      repeatCount: repeatCount,
      mute: mute,
      contentMode: contentMode,
      fps: fps,
      frameEventsEnabled: frameEventsEnabled,
      tagValues: tagValues,
    );
  }

  Future<void> stop() {
    return _platform.stop(_requireViewId());
  }

  Future<void> setMute(bool mute) {
    return _platform.setMute(_requireViewId(), mute);
  }

  Future<void> setContentMode(VapContentMode mode) {
    return _platform.setContentMode(_requireViewId(), mode);
  }

  Future<void> setFrameEventsEnabled(bool enabled) {
    return _platform.setFrameEventsEnabled(_requireViewId(), enabled);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelPendingPlay(
      StateError(
        'Pending play request was cancelled because controller was disposed.',
      ),
    );
    await onViewDisposed();
    await _playbackSubscription.cancel();
    await _clickSubscription.cancel();
    await _playbackEventsController.close();
    await _clickEventsController.close();
  }

  int _requireViewId() {
    _assertNotDisposed();
    final int? currentViewId = _viewId;
    if (currentViewId == null) {
      throw StateError('VapController is not attached to a VapView yet.');
    }
    return currentViewId;
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('VapController is already disposed.');
    }
  }

  VapPlayRequest _toPlayRequest(int viewId, _PlayParams params) {
    return VapPlayRequest(
      viewId: viewId,
      sourceType: params.sourceType,
      source: params.source,
      assetPackage: params.assetPackage,
      repeatCount: params.repeatCount,
      mute: params.mute,
      contentMode: params.contentMode,
      fps: params.fps,
      frameEventsEnabled: params.frameEventsEnabled,
      tagValues: params.tagValues,
    );
  }

  Future<void> _queuePendingPlay(_PlayParams params) {
    _cancelPendingPlay(
      StateError(
        'Pending play request was superseded by a newer play request before attachment.',
      ),
    );
    final _PendingPlay pending = _PendingPlay(
      params: params,
      completer: Completer<void>(),
    );
    _pendingPlay = pending;
    return pending.completer.future;
  }

  void _flushPendingPlay(int viewId) {
    final _PendingPlay? pending = _pendingPlay;
    if (pending == null) {
      return;
    }
    _pendingPlay = null;
    _platform
        .play(_toPlayRequest(viewId, pending.params))
        .then(
          (_) {
            if (!pending.completer.isCompleted) {
              pending.completer.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!pending.completer.isCompleted) {
              pending.completer.completeError(error, stackTrace);
            }
          },
        );
  }

  void _cancelPendingPlay(Object error) {
    final _PendingPlay? pending = _pendingPlay;
    _pendingPlay = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error);
    }
  }
}

class _PlayParams {
  const _PlayParams({
    required this.sourceType,
    required this.source,
    required this.assetPackage,
    required this.repeatCount,
    required this.mute,
    required this.contentMode,
    required this.fps,
    required this.frameEventsEnabled,
    required this.tagValues,
  });

  final VapSourceType sourceType;
  final String source;
  final String? assetPackage;
  final int repeatCount;
  final bool mute;
  final VapContentMode contentMode;
  final int? fps;
  final bool frameEventsEnabled;
  final Map<String, String> tagValues;
}

class _PendingPlay {
  const _PendingPlay({required this.params, required this.completer});

  final _PlayParams params;
  final Completer<void> completer;
}
