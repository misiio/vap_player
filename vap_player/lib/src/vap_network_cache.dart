import 'package:vap_player_platform_interface/vap_player_platform_interface.dart'
    as platform;

import 'vap_models.dart';

abstract final class VapNetworkCache {
  static Future<VapNetworkCacheInfo> info() async {
    final platform.VapPlatformNetworkCacheInfo info = await platform
        .VapPlayerPlatform
        .instance
        .getNetworkCacheInfo();
    return VapNetworkCacheInfo(
      sizeBytes: info.sizeBytes,
      maxBytes: info.maxBytes,
    );
  }

  static Future<void> clear() {
    return platform.VapPlayerPlatform.instance.clearNetworkCache();
  }

  static Future<void> setMaxBytes(int bytes) {
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes', 'must be >= 0');
    }
    return platform.VapPlayerPlatform.instance.setNetworkCacheMaxBytes(bytes);
  }
}
