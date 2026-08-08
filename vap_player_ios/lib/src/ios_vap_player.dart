import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

import 'messages.g.dart' hide vapEvents;
import 'messages.g.dart' as pigeon show vapEvents;

/// The non-test implementation of the per-player API provider.
VapPlayerInstanceApi _productionApiProvider(int playerId) {
  return VapPlayerInstanceApi(messageChannelSuffix: playerId.toString());
}

/// The non-test implementation of the event stream provider.
Stream<PlatformVapEvent> _productionEventStreamProvider(String instanceName) {
  return pigeon.vapEvents(instanceName: instanceName);
}

/// An iOS implementation of [VapPlayerPlatform] backed by the
/// pigeon-generated APIs.
///
/// Rendering always uses a platform view: the native VAP renderer draws
/// into an on-screen CAMetalLayer and cannot feed a Flutter texture, so
/// [VapViewType.textureView] silently falls back to a platform view.
class IosVapPlayer extends VapPlayerPlatform {
  /// Creates a new iOS vap player implementation instance.
  IosVapPlayer({
    @visibleForTesting IosVapPlayerApi? pluginApi,
    @visibleForTesting
    VapPlayerInstanceApi Function(int playerId)? playerApiProvider,
    @visibleForTesting
    Stream<PlatformVapEvent> Function(String instanceName)? eventStreamProvider,
  }) : _api = pluginApi ?? IosVapPlayerApi(),
       _playerApiProvider = playerApiProvider ?? _productionApiProvider,
       _eventStreamProvider =
           eventStreamProvider ?? _productionEventStreamProvider;

  final IosVapPlayerApi _api;
  final VapPlayerInstanceApi Function(int playerId) _playerApiProvider;
  final Stream<PlatformVapEvent> Function(String instanceName)
  _eventStreamProvider;

  final Map<int, VapPlayerInstanceApi> _players = <int, VapPlayerInstanceApi>{};
  final Map<int, VapResourceDelegate> _resourceDelegates =
      <int, VapResourceDelegate>{};
  bool _resourceApiSetUp = false;

  /// Registers this class as the default instance of [VapPlayerPlatform].
  static void registerWith() {
    VapPlayerPlatform.instance = IosVapPlayer();
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
    final int playerId = await _api.create(
      PlatformCreationOptions(enableFrameEvents: options.enableFrameEvents),
    );
    _players[playerId] = _playerApiProvider(playerId);
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
    return _playerWith(playerId).play(
      PlatformPlayOptions(
        path: options.path,
        repeatCount: options.repeatCount,
        mute: options.mute,
        contentMode: switch (options.scaleType) {
          VapScaleType.fitXY => PlatformContentMode.scaleToFill,
          VapScaleType.fitCenter => PlatformContentMode.aspectFit,
          VapScaleType.centerCrop => PlatformContentMode.aspectFill,
        },
        enableOldVersion: options.enableOldVersion,
      ),
    );
  }

  @override
  Future<void> stop(int playerId) {
    return _playerWith(playerId).stop();
  }

  @override
  Future<void> pause(int playerId) {
    return _playerWith(playerId).pause();
  }

  @override
  Future<void> resume(int playerId) {
    return _playerWith(playerId).resume();
  }

  @override
  bool get isPauseResumeSupported => true;

  @override
  Future<void> setMute(int playerId, bool mute) {
    return _playerWith(playerId).setMute(mute);
  }

  @override
  Future<void> setRepeatCount(int playerId, int repeatCount) {
    return _playerWith(playerId).setRepeatCount(repeatCount);
  }

  @override
  void setResourceDelegate(int playerId, VapResourceDelegate? delegate) {
    _ensureResourceApi();
    if (delegate == null) {
      _resourceDelegates.remove(playerId);
    } else {
      _resourceDelegates[playerId] = delegate;
    }
    unawaited(_playerWith(playerId).setHasResourceDelegate(delegate != null));
  }

  @override
  Stream<VapEvent> vapEventsFor(int playerId) {
    return _eventStreamProvider(playerId.toString()).map(_vapEventFromPlatform);
  }

  @override
  Widget buildViewWithOptions(VapViewOptions options) {
    return UiKitView(
      viewType: 'app.misi/vap_player_ios',
      creationParams: options.playerId,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  VapPlayerInstanceApi _playerWith(int playerId) {
    final VapPlayerInstanceApi? player = _players[playerId];
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
    final Future<String?> Function(VapResource)? fetch =
        delegates[playerId]?.resolveText;
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
    final Future<Uint8List?> Function(VapResource)? fetch =
        delegates[playerId]?.resolveImage;
    if (fetch == null) {
      return null;
    }
    return fetch(_resourceFromPlatform(resource));
  }
}
