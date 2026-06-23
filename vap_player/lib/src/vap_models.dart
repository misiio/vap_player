import 'dart:typed_data';

import 'package:flutter/painting.dart';

sealed class VapSource {
  const VapSource._(this.value);

  const factory VapSource.asset(String path, {String? package}) =
      VapAssetSource;

  const factory VapSource.file(String path) = VapFileSource;

  factory VapSource.network(Uri url) {
    final String scheme = url.scheme.toLowerCase();
    final bool valid =
        url.isAbsolute &&
        (scheme == 'http' || scheme == 'https') &&
        url.host.isNotEmpty;
    if (!valid) {
      throw ArgumentError.value(
        url,
        'url',
        'must be an absolute http/https URL',
      );
    }
    return VapNetworkSource._(url);
  }

  final String value;
}

final class VapAssetSource extends VapSource {
  const VapAssetSource(super.value, {this.package}) : super._();

  final String? package;
}

final class VapFileSource extends VapSource {
  const VapFileSource(super.value) : super._();
}

final class VapNetworkSource extends VapSource {
  VapNetworkSource._(this.url) : super._(url.toString());

  final Uri url;
}

class VapPlaybackOptions {
  const VapPlaybackOptions({
    this.loop = false,
    this.muted = false,
    this.fit = BoxFit.fill,
    this.frameEvents = false,
    this.tags = const <String, String>{},
    this.imageResolver,
  });

  final bool loop;
  final bool muted;
  final BoxFit fit;
  final bool frameEvents;
  final Map<String, String> tags;
  final VapImageResolver? imageResolver;
}

sealed class VapEvent {
  const VapEvent();
}

enum VapPlaybackEventType {
  configReady,
  started,
  frame,
  complete,
  destroy,
  stopped,
  failed,
}

final class VapPlaybackEvent extends VapEvent {
  const VapPlaybackEvent({
    required this.type,
    this.frameIndex,
    this.width,
    this.height,
    this.fps,
    this.isMix,
    this.errorCode,
    this.errorMessage,
  });

  final VapPlaybackEventType type;
  final int? frameIndex;
  final int? width;
  final int? height;
  final int? fps;
  final bool? isMix;
  final int? errorCode;
  final String? errorMessage;
}

final class VapResourceClickEvent extends VapEvent {
  const VapResourceClickEvent({
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

class VapImageResolveRequest {
  const VapImageResolveRequest({
    required this.resourceId,
    required this.tag,
    required this.type,
    required this.loadType,
    required this.width,
    required this.height,
    this.url,
  });

  final String resourceId;
  final String tag;
  final String type;
  final String loadType;
  final int width;
  final int height;
  final String? url;
}

typedef VapImageResolver =
    Future<Uint8List?> Function(VapImageResolveRequest request);

class VapNetworkCacheInfo {
  const VapNetworkCacheInfo({required this.sizeBytes, required this.maxBytes});

  final int sizeBytes;
  final int maxBytes;
}
