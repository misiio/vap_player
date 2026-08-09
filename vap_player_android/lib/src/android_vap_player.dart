import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

import 'messages.g.dart' hide vapEvents;
import 'messages.g.dart' as pigeon show vapEvents;
import 'platform_view_player.dart';

/// The non-test implementation of the per-player API provider.
VapPlayerInstanceApi _productionApiProvider(int playerId) {
  return VapPlayerInstanceApi(messageChannelSuffix: playerId.toString());
}

/// The non-test implementation of the event stream provider.
Stream<PlatformVapEvent> _productionEventStreamProvider(String instanceName) {
  return pigeon.vapEvents(instanceName: instanceName);
}

/// An Android implementation of [VapPlayerPlatform] backed by the
/// pigeon-generated APIs.
class AndroidVapPlayer extends VapPlayerPlatform {
  /// Creates a new Android vap player implementation instance.
  AndroidVapPlayer({
    @visibleForTesting AndroidVapPlayerApi? pluginApi,
    @visibleForTesting
    VapPlayerInstanceApi Function(int playerId)? playerApiProvider,
    @visibleForTesting
    Stream<PlatformVapEvent> Function(String instanceName)? eventStreamProvider,
  }) : _api = pluginApi ?? AndroidVapPlayerApi(),
       _playerApiProvider = playerApiProvider ?? _productionApiProvider,
       _eventStreamProvider =
           eventStreamProvider ?? _productionEventStreamProvider;

  final AndroidVapPlayerApi _api;
  final VapPlayerInstanceApi Function(int playerId) _playerApiProvider;
  final Stream<PlatformVapEvent> Function(String instanceName)
  _eventStreamProvider;

  final Map<int, _PlayerInstance> _players = <int, _PlayerInstance>{};
  final Map<int, VapResourceDelegate> _resourceDelegates =
      <int, VapResourceDelegate>{};
  bool _resourceApiSetUp = false;

  /// Registers this class as the default instance of [VapPlayerPlatform].
  static void registerWith() {
    VapPlayerPlatform.instance = AndroidVapPlayer();
  }

  void _ensureResourceApi() {
    if (_resourceApiSetUp) {
      return;
    }
    _resourceApiSetUp = true;
    VapResourceFlutterApi.setUp(_ResourceApiImplementation(_resourceDelegates));
  }

  @override
  Future<void> init() {
    _ensureResourceApi();
    return _api.initialize();
  }

  @override
  Future<int> create(VapCreationOptions options) async {
    _ensureResourceApi();
    final PlatformCreationOptions pigeonOptions = PlatformCreationOptions(
      viewType: switch (options.viewType) {
        VapViewType.textureView => PlatformVapViewType.textureView,
        VapViewType.platformView => PlatformVapViewType.platformView,
      },
      enableFrameEvents: options.enableFrameEvents,
    );

    final int playerId;
    final _VapViewState viewState;
    switch (options.viewType) {
      case VapViewType.textureView:
        final TexturePlayerIds ids = await _api.createForTextureView(
          pigeonOptions,
        );
        playerId = ids.playerId;
        viewState = _TextureVapViewState(ids.textureId);
      case VapViewType.platformView:
        playerId = await _api.createForPlatformView(pigeonOptions);
        viewState = const _PlatformVapViewState();
    }

    _players[playerId] = _PlayerInstance(
      api: _playerApiProvider(playerId),
      viewState: viewState,
    );
    return playerId;
  }

  @override
  Future<void> dispose(int playerId) async {
    _players.remove(playerId);
    _resourceDelegates.remove(playerId);
    await _api.dispose(playerId);
  }

  @override
  Future<void> play(int playerId, VapPlayOptions options) {
    return _playerWith(playerId).api.play(
      PlatformPlayOptions(
        path: options.path,
        repeatCount: options.repeatCount,
        mute: options.mute,
        // The Flutter layout applies the requested fit around both Texture
        // and PlatformView renderers. Keep the native renderer filling that
        // fitted surface; its V1 config arrives too late for native scaling.
        scaleType: PlatformScaleType.fitXY,
        enableOldVersion: options.enableOldVersion,
        fps: options.fps,
      ),
    );
  }

  @override
  Future<void> stop(int playerId) {
    return _playerWith(playerId).api.stop();
  }

  @override
  Future<void> pause(int playerId) {
    throw UnsupportedError(
      'The Android VAP library does not support pausing playback.',
    );
  }

  @override
  Future<void> resume(int playerId) {
    throw UnsupportedError(
      'The Android VAP library does not support resuming playback.',
    );
  }

  @override
  bool get isPauseResumeSupported => false;

  @override
  Future<void> setMute(int playerId, bool mute) {
    return _playerWith(playerId).api.setMute(mute);
  }

  @override
  Future<void> setRepeatCount(int playerId, int repeatCount) {
    return _playerWith(playerId).api.setRepeatCount(repeatCount);
  }

  @override
  void setResourceDelegate(int playerId, VapResourceDelegate? delegate) {
    _ensureResourceApi();
    if (delegate == null) {
      _resourceDelegates.remove(playerId);
    } else {
      _resourceDelegates[playerId] = delegate;
    }
    unawaited(
      _playerWith(playerId).api.setHasResourceDelegate(delegate != null),
    );
  }

  @override
  Stream<VapEvent> vapEventsFor(int playerId) {
    return _eventStreamProvider(playerId.toString()).map(_vapEventFromPlatform);
  }

  @override
  Widget buildViewWithOptions(VapViewOptions options) {
    final int playerId = options.playerId;
    return switch (_playerWith(playerId).viewState) {
      _TextureVapViewState(:final int textureId) => Texture(
        textureId: textureId,
      ),
      _PlatformVapViewState() => PlatformViewPlayer(playerId: playerId),
    };
  }

  _PlayerInstance _playerWith(int playerId) {
    final _PlayerInstance? player = _players[playerId];
    if (player == null) {
      throw StateError('No active player with ID $playerId.');
    }
    return player;
  }

  static VapEvent _vapEventFromPlatform(PlatformVapEvent event) {
    return switch (event) {
      ConfigReadyEvent() => VapConfigReadyEvent(
        width: event.width,
        height: event.height,
        videoWidth: event.videoWidth,
        videoHeight: event.videoHeight,
        frameCount: event.frameCount,
        fps: event.fps,
        isMix: event.isMix,
      ),
      StartedEvent() => const VapStartedEvent(),
      FrameRenderedEvent() => VapFrameEvent(event.frameIndex),
      CompletedEvent() => const VapCompletedEvent(),
      DestroyedEvent() => const VapDestroyedEvent(),
      FailedEvent() => VapErrorEvent(
        code: event.errorType,
        message: event.errorMsg,
      ),
      ResourceClickedEvent() => VapResourceClickEvent(
        _resourceFromPlatform(event.resource),
      ),
    };
  }
}

VapResource _resourceFromPlatform(PlatformVapResource resource) {
  return VapResource(
    id: resource.id,
    type: switch (resource.type) {
      PlatformResourceType.image => VapResourceType.image,
      PlatformResourceType.text => VapResourceType.text,
    },
    tag: resource.tag,
  );
}

class _ResourceApiImplementation implements VapResourceFlutterApi {
  _ResourceApiImplementation(this.delegates);

  final Map<int, VapResourceDelegate> delegates;

  @override
  Future<String?> resolveText(
    int playerId,
    PlatformVapResource resource,
  ) async {
    final VapResourceDelegate? delegate = delegates[playerId];
    final Future<String?> Function(VapResource)? fetch = delegate?.resolveText;
    if (fetch == null) {
      return null;
    }
    return fetch(_resourceFromPlatform(resource));
  }

  @override
  Future<Uint8List?> resolveImage(
    int playerId,
    PlatformVapResource resource,
  ) async {
    final VapResourceDelegate? delegate = delegates[playerId];
    final Future<Uint8List?> Function(VapResource)? fetch =
        delegate?.resolveImage;
    if (fetch == null) {
      return null;
    }
    return fetch(_resourceFromPlatform(resource));
  }
}

sealed class _VapViewState {
  const _VapViewState();
}

class _TextureVapViewState extends _VapViewState {
  const _TextureVapViewState(this.textureId);

  final int textureId;
}

class _PlatformVapViewState extends _VapViewState {
  const _PlatformVapViewState();
}

class _PlayerInstance {
  _PlayerInstance({required this.api, required this.viewState});

  final VapPlayerInstanceApi api;
  final _VapViewState viewState;
}
