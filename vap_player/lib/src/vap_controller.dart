import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart'
    as platform;

import 'vap_models.dart';

class VapController {
  VapController() : _platform = platform.VapPlayerPlatform.instance {
    _eventsSubscription = _platform.events.listen(_handlePlatformEvent);
  }

  final platform.VapPlayerPlatform _platform;
  final StreamController<VapEvent> _eventsController =
      StreamController<VapEvent>.broadcast();

  late final StreamSubscription<platform.VapPlatformEvent> _eventsSubscription;

  int? _viewId;
  VapImageResolver? _imageResolver;
  _PendingPlay? _pendingPlay;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  Stream<VapEvent> get events => _eventsController.stream;

  Future<void> play(
    VapSource source, {
    VapPlaybackOptions options = const VapPlaybackOptions(),
  }) {
    _assertNotDisposed();
    final _PlayParams params = _PlayParams(source: source, options: options);
    _imageResolver = options.imageResolver;

    final int? currentViewId = _viewId;
    if (currentViewId != null) {
      _platform.setImageResolver(
        currentViewId,
        _toPlatformImageResolver(options.imageResolver),
      );
      return _platform.play(_toPlayRequest(currentViewId, params));
    }
    return _queuePendingPlay(params);
  }

  Future<void> stop() {
    _assertNotDisposed();
    _cancelPendingPlay(
      StateError(
        'Pending play request was cancelled because playback stopped.',
      ),
    );
    return _platform.stop(_requireViewId());
  }

  Future<void> dispose() {
    final Future<void>? inFlightDispose = _disposeFuture;
    if (inFlightDispose != null) {
      return inFlightDispose;
    }

    final Future<void> disposeFuture = _disposeInternal();
    _disposeFuture = disposeFuture;
    return disposeFuture;
  }

  @internal
  void attach(int viewId) {
    _assertNotDisposed();
    if (_viewId == viewId) {
      return;
    }
    if (_viewId != null && _viewId != viewId) {
      throw StateError(
        'This VapController is already attached to a platform view.',
      );
    }
    _viewId = viewId;
    _platform.setImageResolver(
      viewId,
      _toPlatformImageResolver(_imageResolver),
    );
    _flushPendingPlay(viewId);
  }

  @internal
  void onViewDetached() {
    _detachView(
      pendingPlayError: StateError(
        'Pending play request was cancelled because the controller was detached from the view.',
      ),
    );
  }

  @internal
  Future<void> onViewDisposed() async {
    final int? currentViewId = _detachView(
      pendingPlayError: StateError(
        'Pending play request was cancelled because the view was disposed.',
      ),
    );
    if (currentViewId != null) {
      try {
        await _platform.dispose(currentViewId);
      } catch (error) {
        if (!_isViewAlreadyDisposedError(error, currentViewId)) {
          rethrow;
        }
      }
    }
  }

  Future<void> _disposeInternal() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelPendingPlay(
      StateError(
        'Pending play request was cancelled because controller was disposed.',
      ),
    );

    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> runDisposeStep(Future<void> Function() step) async {
      try {
        await step();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await runDisposeStep(onViewDisposed);
    await runDisposeStep(_eventsSubscription.cancel);
    await runDisposeStep(_eventsController.close);

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  void _handlePlatformEvent(platform.VapPlatformEvent event) {
    if (_viewId != event.viewId) {
      return;
    }
    switch (event) {
      case platform.VapPlatformPlaybackEvent():
        _eventsController.add(
          VapPlaybackEvent(
            type: _fromPlatformPlaybackEventType(event.type),
            frameIndex: event.frameIndex,
            width: event.width,
            height: event.height,
            fps: event.fps,
            isMix: event.isMix,
            errorCode: event.errorCode,
            errorMessage: event.errorMessage,
          ),
        );
      case platform.VapPlatformResourceClickEvent():
        _eventsController.add(
          VapResourceClickEvent(
            resourceId: event.resourceId,
            tag: event.tag,
            x: event.x,
            y: event.y,
            width: event.width,
            height: event.height,
          ),
        );
    }
  }

  int? _detachView({required Object pendingPlayError}) {
    _cancelPendingPlay(pendingPlayError);
    final int? currentViewId = _viewId;
    _viewId = null;
    if (currentViewId != null) {
      _platform.setImageResolver(currentViewId, null);
    }
    return currentViewId;
  }

  int _requireViewId() {
    _assertNotDisposed();
    final int? currentViewId = _viewId;
    if (currentViewId == null) {
      throw StateError('VapController is not attached to a VapPlayer yet.');
    }
    return currentViewId;
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('VapController is already disposed.');
    }
  }

  platform.VapPlatformPlayRequest _toPlayRequest(
    int viewId,
    _PlayParams params,
  ) {
    final VapSource source = params.source;
    return platform.VapPlatformPlayRequest(
      viewId: viewId,
      sourceType: _toPlatformSourceType(source),
      source: source.value,
      assetPackage: source is VapAssetSource ? source.package : null,
      loop: params.options.loop,
      muted: params.options.muted,
      contentMode: _toPlatformContentMode(params.options.fit),
      frameEvents: params.options.frameEvents,
      tagValues: params.options.tags,
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
    _platform.setImageResolver(
      viewId,
      _toPlatformImageResolver(pending.params.options.imageResolver),
    );
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

  platform.VapPlatformImageResolver? _toPlatformImageResolver(
    VapImageResolver? resolver,
  ) {
    if (resolver == null) {
      return null;
    }
    return (platform.VapPlatformImageResolveRequest request) {
      return resolver(
        VapImageResolveRequest(
          resourceId: request.resourceId,
          tag: request.tag,
          type: request.type,
          loadType: request.loadType,
          width: request.width,
          height: request.height,
          url: request.url,
        ),
      );
    };
  }

  bool _isViewAlreadyDisposedError(Object error, int viewId) {
    if (error is PlatformException) {
      if (error.code == 'not-found') {
        return true;
      }
      final String? message = error.message;
      if (message != null &&
          message.contains('No VapView found for viewId=$viewId')) {
        return true;
      }
    }
    return error.toString().contains('No VapView found for viewId=$viewId');
  }

  static platform.VapPlatformSourceType _toPlatformSourceType(
    VapSource source,
  ) {
    switch (source) {
      case VapAssetSource():
        return platform.VapPlatformSourceType.asset;
      case VapFileSource():
        return platform.VapPlatformSourceType.file;
      case VapNetworkSource():
        return platform.VapPlatformSourceType.network;
    }
  }

  static platform.VapPlatformContentMode _toPlatformContentMode(BoxFit fit) {
    switch (fit) {
      case BoxFit.fill:
        return platform.VapPlatformContentMode.scaleToFill;
      case BoxFit.contain:
        return platform.VapPlatformContentMode.aspectFit;
      case BoxFit.cover:
        return platform.VapPlatformContentMode.aspectFill;
      case BoxFit.fitWidth:
      case BoxFit.fitHeight:
      case BoxFit.none:
      case BoxFit.scaleDown:
        throw ArgumentError.value(
          fit,
          'fit',
          'Only BoxFit.fill, BoxFit.contain, and BoxFit.cover are supported.',
        );
    }
  }

  static VapPlaybackEventType _fromPlatformPlaybackEventType(
    platform.VapPlatformPlaybackEventType type,
  ) {
    switch (type) {
      case platform.VapPlatformPlaybackEventType.configReady:
        return VapPlaybackEventType.configReady;
      case platform.VapPlatformPlaybackEventType.started:
        return VapPlaybackEventType.started;
      case platform.VapPlatformPlaybackEventType.frame:
        return VapPlaybackEventType.frame;
      case platform.VapPlatformPlaybackEventType.complete:
        return VapPlaybackEventType.complete;
      case platform.VapPlatformPlaybackEventType.destroy:
        return VapPlaybackEventType.destroy;
      case platform.VapPlatformPlaybackEventType.stopped:
        return VapPlaybackEventType.stopped;
      case platform.VapPlatformPlaybackEventType.failed:
        return VapPlaybackEventType.failed;
    }
  }
}

class _PlayParams {
  const _PlayParams({required this.source, required this.options});

  final VapSource source;
  final VapPlaybackOptions options;
}

class _PendingPlay {
  const _PendingPlay({required this.params, required this.completer});

  final _PlayParams params;
  final Completer<void> completer;
}
