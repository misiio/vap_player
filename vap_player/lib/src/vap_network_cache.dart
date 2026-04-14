import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

/// Process-wide network cache controls for vap_player.
abstract final class VapNetworkCache {
  static Future<int> sizeBytes() {
    return VapPlayerPlatform.instance.getNetworkCacheSizeBytes();
  }

  static Future<void> clear() {
    return VapPlayerPlatform.instance.clearNetworkCache();
  }

  static Future<void> pruneToBytes(int maxBytes) {
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be >= 0');
    }
    return VapPlayerPlatform.instance.pruneNetworkCacheToBytes(maxBytes);
  }
}
