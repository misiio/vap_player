import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vap_player/flutter_vap_player.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart'
    as platform;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVapPlayerPlatform fakePlatform;
  late platform.VapPlayerPlatform previousPlatform;

  setUp(() {
    fakePlatform = FakeVapPlayerPlatform();
    previousPlatform = platform.VapPlayerPlatform.instance;
    platform.VapPlayerPlatform.instance = fakePlatform;
  });

  tearDown(() {
    platform.VapPlayerPlatform.instance = previousPlatform;
  });

  test('VapNetworkCache forwards info, clear, and max size requests', () async {
    fakePlatform.cacheInfo = const platform.VapPlatformNetworkCacheInfo(
      sizeBytes: 1234,
      maxBytes: 4096,
    );

    final VapNetworkCacheInfo info = await VapNetworkCache.info();
    await VapNetworkCache.clear();
    await VapNetworkCache.setMaxBytes(2048);

    expect(info.sizeBytes, 1234);
    expect(info.maxBytes, 4096);
    expect(fakePlatform.clearNetworkCacheCalls, 1);
    expect(fakePlatform.lastSetNetworkCacheMaxBytes, 2048);
  });

  test('VapNetworkCache rejects negative max size', () async {
    expect(() => VapNetworkCache.setMaxBytes(-1), throwsArgumentError);
  });
}

class FakeVapPlayerPlatform extends platform.VapPlayerPlatform {
  final StreamController<platform.VapPlatformEvent> _eventsController =
      StreamController<platform.VapPlatformEvent>.broadcast();

  platform.VapPlatformNetworkCacheInfo cacheInfo =
      const platform.VapPlatformNetworkCacheInfo(sizeBytes: 0, maxBytes: 0);
  int clearNetworkCacheCalls = 0;
  int? lastSetNetworkCacheMaxBytes;

  @override
  Stream<platform.VapPlatformEvent> get events => _eventsController.stream;

  @override
  void setImageResolver(
    int viewId,
    platform.VapPlatformImageResolver? resolver,
  ) {}

  @override
  Future<void> play(platform.VapPlatformPlayRequest request) async {}

  @override
  Future<void> stop(int viewId) async {}

  @override
  Future<void> dispose(int viewId) async {}

  @override
  Future<platform.VapPlatformNetworkCacheInfo> getNetworkCacheInfo() async {
    return cacheInfo;
  }

  @override
  Future<void> clearNetworkCache() async {
    clearNetworkCacheCalls += 1;
  }

  @override
  Future<void> setNetworkCacheMaxBytes(int maxBytes) async {
    lastSetNetworkCacheMaxBytes = maxBytes;
  }
}
