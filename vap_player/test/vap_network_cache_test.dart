import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vap_player/flutter_vap_player.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVapPlayerPlatform fakePlatform;
  final VapPlayerPlatform previousPlatform = VapPlayerPlatform.instance;

  setUp(() {
    fakePlatform = _FakeVapPlayerPlatform();
    VapPlayerPlatform.instance = fakePlatform;
  });

  tearDown(() {
    VapPlayerPlatform.instance = previousPlatform;
  });

  test('VapNetworkCache forwards size, clear, and prune requests', () async {
    fakePlatform.networkCacheSizeBytes = 2048;

    final int size = await VapNetworkCache.sizeBytes();
    await VapNetworkCache.clear();
    await VapNetworkCache.pruneToBytes(1024);

    expect(size, 2048);
    expect(fakePlatform.clearCalls, 1);
    expect(fakePlatform.lastPruneMaxBytes, 1024);
  });

  test('VapNetworkCache rejects negative prune target', () async {
    expect(() => VapNetworkCache.pruneToBytes(-1), throwsArgumentError);
    expect(fakePlatform.lastPruneMaxBytes, isNull);
  });

  test('VapNetworkCache forwards get/set auto-eviction max bytes', () async {
    fakePlatform.autoEvictionMaxBytes = 4096;

    final int current = await VapNetworkCache.autoEvictionMaxBytes();
    await VapNetworkCache.setAutoEvictionMaxBytes(2048);

    expect(current, 4096);
    expect(fakePlatform.lastSetAutoEvictionMaxBytes, 2048);
  });

  test('VapNetworkCache rejects negative auto-eviction target', () async {
    expect(
      () => VapNetworkCache.setAutoEvictionMaxBytes(-1),
      throwsArgumentError,
    );
    expect(fakePlatform.lastSetAutoEvictionMaxBytes, isNull);
  });
}

class _FakeVapPlayerPlatform extends VapPlayerPlatform {
  final StreamController<VapPlaybackEvent> _playbackController =
      StreamController<VapPlaybackEvent>.broadcast();
  final StreamController<VapResourceClickEvent> _clickController =
      StreamController<VapResourceClickEvent>.broadcast();

  int networkCacheSizeBytes = 0;
  int clearCalls = 0;
  int? lastPruneMaxBytes;
  int autoEvictionMaxBytes = 0;
  int? lastSetAutoEvictionMaxBytes;

  @override
  Stream<VapPlaybackEvent> get playbackEvents => _playbackController.stream;

  @override
  Stream<VapResourceClickEvent> get clickEvents => _clickController.stream;

  @override
  void setImageResolver(int viewId, VapImageResolver? resolver) {}

  @override
  Future<void> play(VapPlayRequest request) async {}

  @override
  Future<void> stop(int viewId) async {}

  @override
  Future<void> setMute(int viewId, bool mute) async {}

  @override
  Future<void> setContentMode(int viewId, VapContentMode mode) async {}

  @override
  Future<void> setFrameEventsEnabled(int viewId, bool enabled) async {}

  @override
  Future<void> dispose(int viewId) async {}

  @override
  Future<int> getNetworkCacheSizeBytes() async {
    return networkCacheSizeBytes;
  }

  @override
  Future<void> clearNetworkCache() async {
    clearCalls += 1;
  }

  @override
  Future<void> pruneNetworkCacheToBytes(int maxBytes) async {
    lastPruneMaxBytes = maxBytes;
  }

  @override
  Future<int> getNetworkAutoEvictionMaxBytes() async {
    return autoEvictionMaxBytes;
  }

  @override
  Future<void> setNetworkAutoEvictionMaxBytes(int maxBytes) async {
    lastSetAutoEvictionMaxBytes = maxBytes;
  }
}
