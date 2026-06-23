import 'dart:typed_data';

enum VapPlatformSourceType { asset, file, network }

enum VapPlatformContentMode { scaleToFill, aspectFit, aspectFill }

enum VapPlatformPlaybackEventType {
  configReady,
  started,
  frame,
  complete,
  destroy,
  stopped,
  failed,
}

abstract final class VapNetworkFailureCode {
  static const int invalidUrl = 1001;
  static const int httpStatus = 1002;
  static const int sizeExceeded = 1003;
  static const int invalidMedia = 1004;
  static const int networkIo = 1005;
}

class VapPlatformPlayRequest {
  const VapPlatformPlayRequest({
    required this.viewId,
    required this.sourceType,
    required this.source,
    this.assetPackage,
    this.loop = false,
    this.muted = false,
    this.contentMode = VapPlatformContentMode.scaleToFill,
    this.frameEvents = false,
    this.tagValues = const <String, String>{},
  });

  final int viewId;
  final VapPlatformSourceType sourceType;
  final String source;
  final String? assetPackage;
  final bool loop;
  final bool muted;
  final VapPlatformContentMode contentMode;
  final bool frameEvents;
  final Map<String, String> tagValues;
}

sealed class VapPlatformEvent {
  const VapPlatformEvent({required this.viewId});

  final int viewId;
}

class VapPlatformPlaybackEvent extends VapPlatformEvent {
  const VapPlatformPlaybackEvent({
    required super.viewId,
    required this.type,
    this.frameIndex,
    this.width,
    this.height,
    this.fps,
    this.isMix,
    this.errorCode,
    this.errorMessage,
  });

  final VapPlatformPlaybackEventType type;
  final int? frameIndex;
  final int? width;
  final int? height;
  final int? fps;
  final bool? isMix;
  final int? errorCode;
  final String? errorMessage;
}

class VapPlatformResourceClickEvent extends VapPlatformEvent {
  const VapPlatformResourceClickEvent({
    required super.viewId,
    this.resourceId,
    this.tag,
    this.x,
    this.y,
    this.width,
    this.height,
  });

  final String? resourceId;
  final String? tag;
  final double? x;
  final double? y;
  final double? width;
  final double? height;
}

class VapPlatformImageResolveRequest {
  const VapPlatformImageResolveRequest({
    required this.viewId,
    required this.resourceId,
    required this.tag,
    required this.type,
    required this.loadType,
    required this.width,
    required this.height,
    this.url,
  });

  final int viewId;
  final String resourceId;
  final String tag;
  final String type;
  final String loadType;
  final int width;
  final int height;
  final String? url;
}

class VapPlatformNetworkCacheInfo {
  const VapPlatformNetworkCacheInfo({
    required this.sizeBytes,
    required this.maxBytes,
  });

  final int sizeBytes;
  final int maxBytes;
}

typedef VapPlatformImageResolver =
    Future<Uint8List?> Function(VapPlatformImageResolveRequest request);
