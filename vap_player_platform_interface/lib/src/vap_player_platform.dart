import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models.dart';
import 'pigeon/vap_player_messages.g.dart';

abstract class VapPlayerPlatform extends PlatformInterface {
  VapPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VapPlayerPlatform _instance = PigeonVapPlayerPlatform();

  static VapPlayerPlatform get instance => _instance;

  static set instance(VapPlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<VapPlatformEvent> get events;

  void setImageResolver(int viewId, VapPlatformImageResolver? resolver);

  Future<void> play(VapPlatformPlayRequest request);

  Future<void> stop(int viewId);

  Future<void> dispose(int viewId);

  Future<VapPlatformNetworkCacheInfo> getNetworkCacheInfo();

  Future<void> clearNetworkCache();

  Future<void> setNetworkCacheMaxBytes(int maxBytes);
}

class PigeonVapPlayerPlatform extends VapPlayerPlatform {
  PigeonVapPlayerPlatform({VapHostApi? hostApi})
    : _hostApi = hostApi ?? VapHostApi() {
    VapEventApi.setUp(_VapEventApiHandler(this));
    VapResourceApi.setUp(_VapResourceApiHandler(this));
  }

  final VapHostApi _hostApi;
  final Map<int, VapPlatformImageResolver> _imageResolvers =
      <int, VapPlatformImageResolver>{};

  final StreamController<VapPlatformEvent> _eventsController =
      StreamController<VapPlatformEvent>.broadcast();

  @override
  Stream<VapPlatformEvent> get events => _eventsController.stream;

  @override
  void setImageResolver(int viewId, VapPlatformImageResolver? resolver) {
    if (resolver == null) {
      _imageResolvers.remove(viewId);
      return;
    }
    _imageResolvers[viewId] = resolver;
  }

  @override
  Future<void> play(VapPlatformPlayRequest request) {
    final Map<String?, String?>? tagValues = request.tagValues.isEmpty
        ? null
        : request.tagValues.map((String key, String value) {
            return MapEntry<String?, String?>(key, value);
          });
    return _hostApi.play(
      VapPlayRequestMessage(
        viewId: request.viewId,
        sourceType: _toSourceTypeMessage(request.sourceType),
        source: request.source,
        assetPackage: request.assetPackage,
        loop: request.loop,
        muted: request.muted,
        contentMode: _toContentModeMessage(request.contentMode),
        frameEvents: request.frameEvents,
        tagValues: tagValues,
      ),
    );
  }

  @override
  Future<void> stop(int viewId) {
    return _hostApi.stop(viewId);
  }

  @override
  Future<void> dispose(int viewId) {
    _imageResolvers.remove(viewId);
    return _hostApi.dispose(viewId);
  }

  @override
  Future<VapPlatformNetworkCacheInfo> getNetworkCacheInfo() async {
    final VapNetworkCacheInfoMessage info = await _hostApi
        .getNetworkCacheInfo();
    return VapPlatformNetworkCacheInfo(
      sizeBytes: info.sizeBytes ?? 0,
      maxBytes: info.maxBytes ?? 0,
    );
  }

  @override
  Future<void> clearNetworkCache() {
    return _hostApi.clearNetworkCache();
  }

  @override
  Future<void> setNetworkCacheMaxBytes(int maxBytes) {
    return _hostApi.setNetworkCacheMaxBytes(maxBytes);
  }

  void addEvent(VapEventMessage event) {
    final int viewId = event.viewId ?? -1;
    switch (event.kind ?? VapEventKindMessage.playback) {
      case VapEventKindMessage.playback:
        _eventsController.add(
          VapPlatformPlaybackEvent(
            viewId: viewId,
            type: _fromPlaybackEventTypeMessage(
              event.playbackType ?? VapPlaybackEventTypeMessage.failed,
            ),
            frameIndex: event.frameIndex,
            width: event.width,
            height: event.height,
            fps: event.fps,
            isMix: event.isMix,
            errorCode: event.errorCode,
            errorMessage: event.errorMessage,
          ),
        );
      case VapEventKindMessage.resourceClick:
        _eventsController.add(
          VapPlatformResourceClickEvent(
            viewId: viewId,
            resourceId: event.resourceId,
            tag: event.tag,
            x: event.x,
            y: event.y,
            width: event.resourceWidth,
            height: event.resourceHeight,
          ),
        );
    }
  }

  Future<VapImageResolveResultMessage> resolveImage(
    VapImageResolveRequestMessage request,
  ) async {
    final int viewId = request.viewId ?? -1;
    final VapPlatformImageResolver? resolver = _imageResolvers[viewId];
    if (resolver == null) {
      return VapImageResolveResultMessage(
        imageBytes: null,
        errorMessage: 'No image resolver registered for viewId=$viewId.',
      );
    }

    try {
      final imageBytes = await resolver(
        VapPlatformImageResolveRequest(
          viewId: viewId,
          resourceId: request.resourceId ?? '',
          tag: request.tag ?? '',
          type: request.type ?? '',
          loadType: request.loadType ?? '',
          width: request.width ?? 0,
          height: request.height ?? 0,
          url: request.url,
        ),
      );
      return VapImageResolveResultMessage(imageBytes: imageBytes);
    } catch (e) {
      return VapImageResolveResultMessage(
        imageBytes: null,
        errorMessage: e.toString(),
      );
    }
  }

  static VapSourceTypeMessage _toSourceTypeMessage(
    VapPlatformSourceType sourceType,
  ) {
    switch (sourceType) {
      case VapPlatformSourceType.asset:
        return VapSourceTypeMessage.asset;
      case VapPlatformSourceType.file:
        return VapSourceTypeMessage.file;
      case VapPlatformSourceType.network:
        return VapSourceTypeMessage.network;
    }
  }

  static VapContentModeMessage _toContentModeMessage(
    VapPlatformContentMode mode,
  ) {
    switch (mode) {
      case VapPlatformContentMode.scaleToFill:
        return VapContentModeMessage.scaleToFill;
      case VapPlatformContentMode.aspectFit:
        return VapContentModeMessage.aspectFit;
      case VapPlatformContentMode.aspectFill:
        return VapContentModeMessage.aspectFill;
    }
  }

  static VapPlatformPlaybackEventType _fromPlaybackEventTypeMessage(
    VapPlaybackEventTypeMessage type,
  ) {
    switch (type) {
      case VapPlaybackEventTypeMessage.configReady:
        return VapPlatformPlaybackEventType.configReady;
      case VapPlaybackEventTypeMessage.started:
        return VapPlatformPlaybackEventType.started;
      case VapPlaybackEventTypeMessage.frame:
        return VapPlatformPlaybackEventType.frame;
      case VapPlaybackEventTypeMessage.complete:
        return VapPlatformPlaybackEventType.complete;
      case VapPlaybackEventTypeMessage.destroy:
        return VapPlatformPlaybackEventType.destroy;
      case VapPlaybackEventTypeMessage.stopped:
        return VapPlatformPlaybackEventType.stopped;
      case VapPlaybackEventTypeMessage.failed:
        return VapPlatformPlaybackEventType.failed;
    }
  }
}

class _VapEventApiHandler extends VapEventApi {
  _VapEventApiHandler(this._platform);

  final PigeonVapPlayerPlatform _platform;

  @override
  void onEvent(VapEventMessage event) {
    _platform.addEvent(event);
  }
}

class _VapResourceApiHandler extends VapResourceApi {
  _VapResourceApiHandler(this._platform);

  final PigeonVapPlayerPlatform _platform;

  @override
  Future<VapImageResolveResultMessage> resolveImage(
    VapImageResolveRequestMessage request,
  ) {
    return _platform.resolveImage(request);
  }
}
