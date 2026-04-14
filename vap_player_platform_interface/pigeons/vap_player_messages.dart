import 'package:pigeon/pigeon.dart';

enum VapSourceTypeMessage { asset, file, network }

enum VapContentModeMessage { scaleToFill, aspectFit, aspectFill }

enum VapPlaybackEventTypeMessage {
  configReady,
  start,
  frame,
  complete,
  destroy,
  stopped,
  failed,
}

class VapPlayRequestMessage {
  int? viewId;
  VapSourceTypeMessage? sourceType;
  String? source;
  String? assetPackage;
  int? repeatCount;
  bool? mute;
  VapContentModeMessage? contentMode;
  int? fps;
  bool? frameEventsEnabled;
  Map<String?, String?>? tagValues;
}

class VapPlaybackEventMessage {
  int? viewId;
  VapPlaybackEventTypeMessage? type;
  int? frameIndex;
  int? width;
  int? height;
  int? fps;
  bool? isMix;
  int? errorCode;
  String? errorMessage;
}

class VapResourceClickEventMessage {
  int? viewId;
  String? resourceId;
  String? tag;
  double? x;
  double? y;
  double? width;
  double? height;
}

class VapImageResolveRequestMessage {
  int? viewId;
  String? resourceId;
  String? tag;
  String? type;
  String? loadType;
  int? width;
  int? height;
  String? url;
}

class VapImageResolveResultMessage {
  Uint8List? imageBytes;
  String? errorMessage;
}

@HostApi()
abstract class VapHostApi {
  void play(VapPlayRequestMessage request);

  void stop(int viewId);

  void setMute(int viewId, bool mute);

  void setContentMode(int viewId, VapContentModeMessage mode);

  void setFrameEventsEnabled(int viewId, bool enabled);

  void dispose(int viewId);

  @async
  int getNetworkCacheSizeBytes();

  void clearNetworkCache();

  void pruneNetworkCacheToBytes(int maxBytes);

  @async
  int getNetworkAutoEvictionMaxBytes();

  void setNetworkAutoEvictionMaxBytes(int maxBytes);
}

@FlutterApi()
abstract class VapEventApi {
  void onPlaybackEvent(VapPlaybackEventMessage event);

  void onResourceClick(VapResourceClickEventMessage event);
}

@FlutterApi()
abstract class VapResourceApi {
  @async
  VapImageResolveResultMessage resolveImage(
    VapImageResolveRequestMessage request,
  );
}
