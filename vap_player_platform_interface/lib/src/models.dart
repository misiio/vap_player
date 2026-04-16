import 'dart:typed_data';

enum VapSourceType { asset, file, network }

enum VapContentMode { scaleToFill, aspectFit, aspectFill }

enum VapPlaybackEventType {
  configReady,
  started,
  frame,
  complete,
  destroy,
  stopped,
  failed,
}

class VapPlayRequest {
  const VapPlayRequest({
    required this.viewId,
    required this.sourceType,
    required this.source,
    this.assetPackage,
    this.repeatCount = 0,
    this.mute = false,
    this.contentMode = VapContentMode.scaleToFill,
    this.fps,
    this.frameEventsEnabled = false,
    this.tagValues = const <String, String>{},
  });

  final int viewId;
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

class VapPlaybackEvent {
  const VapPlaybackEvent({
    required this.viewId,
    required this.type,
    this.frameIndex,
    this.width,
    this.height,
    this.fps,
    this.isMix,
    this.errorCode,
    this.errorMessage,
  });

  final int viewId;
  final VapPlaybackEventType type;
  final int? frameIndex;
  final int? width;
  final int? height;
  final int? fps;
  final bool? isMix;
  final int? errorCode;
  final String? errorMessage;
}

class VapResourceClickEvent {
  const VapResourceClickEvent({
    required this.viewId,
    this.resourceId,
    this.tag,
    this.x,
    this.y,
    this.width,
    this.height,
  });

  final int viewId;
  final String? resourceId;
  final String? tag;
  final double? x;
  final double? y;
  final double? width;
  final double? height;
}

class VapImageResolveRequest {
  const VapImageResolveRequest({
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

class VapImageResolveResult {
  const VapImageResolveResult({this.imageBytes, this.errorMessage});

  final Uint8List? imageBytes;
  final String? errorMessage;
}

typedef VapImageResolver =
    Future<Uint8List?> Function(VapImageResolveRequest request);
