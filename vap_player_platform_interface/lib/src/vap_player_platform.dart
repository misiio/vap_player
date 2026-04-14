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

  Stream<VapPlaybackEvent> get playbackEvents;

  Stream<VapResourceClickEvent> get clickEvents;

  void setImageResolver(int viewId, VapImageResolver? resolver);

  Future<void> play(VapPlayRequest request);

  Future<void> stop(int viewId);

  Future<void> setMute(int viewId, bool mute);

  Future<void> setContentMode(int viewId, VapContentMode mode);

  Future<void> setFrameEventsEnabled(int viewId, bool enabled);

  Future<void> dispose(int viewId);
}

class PigeonVapPlayerPlatform extends VapPlayerPlatform {
  PigeonVapPlayerPlatform({VapHostApi? hostApi})
    : _hostApi = hostApi ?? VapHostApi() {
    VapEventApi.setUp(_VapEventApiHandler(this));
    VapResourceApi.setUp(_VapResourceApiHandler(this));
  }

  final VapHostApi _hostApi;
  final Map<int, VapImageResolver> _imageResolvers = <int, VapImageResolver>{};

  final StreamController<VapPlaybackEvent> _playbackEventsController =
      StreamController<VapPlaybackEvent>.broadcast();
  final StreamController<VapResourceClickEvent> _clickEventsController =
      StreamController<VapResourceClickEvent>.broadcast();

  @override
  Stream<VapPlaybackEvent> get playbackEvents =>
      _playbackEventsController.stream;

  @override
  Stream<VapResourceClickEvent> get clickEvents =>
      _clickEventsController.stream;

  @override
  void setImageResolver(int viewId, VapImageResolver? resolver) {
    if (resolver == null) {
      _imageResolvers.remove(viewId);
      return;
    }
    _imageResolvers[viewId] = resolver;
  }

  @override
  Future<void> play(VapPlayRequest request) {
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
        repeatCount: request.repeatCount,
        mute: request.mute,
        contentMode: _toContentModeMessage(request.contentMode),
        fps: request.fps,
        frameEventsEnabled: request.frameEventsEnabled,
        tagValues: tagValues,
      ),
    );
  }

  @override
  Future<void> stop(int viewId) {
    return _hostApi.stop(viewId);
  }

  @override
  Future<void> setMute(int viewId, bool mute) {
    return _hostApi.setMute(viewId, mute);
  }

  @override
  Future<void> setContentMode(int viewId, VapContentMode mode) {
    return _hostApi.setContentMode(viewId, _toContentModeMessage(mode));
  }

  @override
  Future<void> setFrameEventsEnabled(int viewId, bool enabled) {
    return _hostApi.setFrameEventsEnabled(viewId, enabled);
  }

  @override
  Future<void> dispose(int viewId) {
    _imageResolvers.remove(viewId);
    return _hostApi.dispose(viewId);
  }

  void addPlaybackEvent(VapPlaybackEventMessage event) {
    _playbackEventsController.add(
      VapPlaybackEvent(
        viewId: event.viewId ?? -1,
        type: _fromPlaybackEventTypeMessage(
          event.type ?? VapPlaybackEventTypeMessage.failed,
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
  }

  void addClickEvent(VapResourceClickEventMessage event) {
    _clickEventsController.add(
      VapResourceClickEvent(
        viewId: event.viewId ?? -1,
        resourceId: event.resourceId,
        tag: event.tag,
        x: event.x,
        y: event.y,
        width: event.width,
        height: event.height,
      ),
    );
  }

  Future<VapImageResolveResultMessage> resolveImage(
    VapImageResolveRequestMessage request,
  ) async {
    final int viewId = request.viewId ?? -1;
    final VapImageResolver? resolver = _imageResolvers[viewId];
    if (resolver == null) {
      return VapImageResolveResultMessage(
        imageBytes: null,
        errorMessage: 'No image resolver registered for viewId=$viewId.',
      );
    }

    try {
      final imageBytes = await resolver(
        VapImageResolveRequest(
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

  static VapSourceTypeMessage _toSourceTypeMessage(VapSourceType sourceType) {
    switch (sourceType) {
      case VapSourceType.asset:
        return VapSourceTypeMessage.asset;
      case VapSourceType.file:
        return VapSourceTypeMessage.file;
    }
  }

  static VapContentModeMessage _toContentModeMessage(VapContentMode mode) {
    switch (mode) {
      case VapContentMode.scaleToFill:
        return VapContentModeMessage.scaleToFill;
      case VapContentMode.aspectFit:
        return VapContentModeMessage.aspectFit;
      case VapContentMode.aspectFill:
        return VapContentModeMessage.aspectFill;
    }
  }

  static VapPlaybackEventType _fromPlaybackEventTypeMessage(
    VapPlaybackEventTypeMessage type,
  ) {
    switch (type) {
      case VapPlaybackEventTypeMessage.configReady:
        return VapPlaybackEventType.configReady;
      case VapPlaybackEventTypeMessage.start:
        return VapPlaybackEventType.start;
      case VapPlaybackEventTypeMessage.frame:
        return VapPlaybackEventType.frame;
      case VapPlaybackEventTypeMessage.complete:
        return VapPlaybackEventType.complete;
      case VapPlaybackEventTypeMessage.destroy:
        return VapPlaybackEventType.destroy;
      case VapPlaybackEventTypeMessage.stopped:
        return VapPlaybackEventType.stopped;
      case VapPlaybackEventTypeMessage.failed:
        return VapPlaybackEventType.failed;
    }
  }
}

class _VapEventApiHandler extends VapEventApi {
  _VapEventApiHandler(this._platform);

  final PigeonVapPlayerPlatform _platform;

  @override
  void onPlaybackEvent(VapPlaybackEventMessage event) {
    _platform.addPlaybackEvent(event);
  }

  @override
  void onResourceClick(VapResourceClickEventMessage event) {
    _platform.addClickEvent(event);
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
