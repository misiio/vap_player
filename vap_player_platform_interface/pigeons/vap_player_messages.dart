import 'package:pigeon/pigeon.dart';

enum VapSourceTypeMessage { asset, file, network }

enum VapContentModeMessage { scaleToFill, aspectFit, aspectFill }

enum VapEventKindMessage { playback, resourceClick }

enum VapPlaybackEventTypeMessage {
  configReady,
  started,
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
  bool? loop;
  bool? muted;
  VapContentModeMessage? contentMode;
  bool? frameEvents;
  Map<String?, String?>? tagValues;
}

class VapEventMessage {
  int? viewId;
  VapEventKindMessage? kind;
  VapPlaybackEventTypeMessage? playbackType;
  int? frameIndex;
  int? width;
  int? height;
  int? fps;
  bool? isMix;
  int? errorCode;
  String? errorMessage;
  String? resourceId;
  String? tag;
  double? x;
  double? y;
  double? resourceWidth;
  double? resourceHeight;
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

class VapNetworkCacheInfoMessage {
  int? sizeBytes;
  int? maxBytes;
}

@HostApi()
abstract class VapHostApi {
  void play(VapPlayRequestMessage request);

  void stop(int viewId);

  void dispose(int viewId);

  @async
  VapNetworkCacheInfoMessage getNetworkCacheInfo();

  void clearNetworkCache();

  void setNetworkCacheMaxBytes(int maxBytes);
}

@FlutterApi()
abstract class VapEventApi {
  void onEvent(VapEventMessage event);
}

@FlutterApi()
abstract class VapResourceApi {
  @async
  VapImageResolveResultMessage resolveImage(
    VapImageResolveRequestMessage request,
  );
}
