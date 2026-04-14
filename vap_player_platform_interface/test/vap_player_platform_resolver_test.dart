import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vap_player_platform_interface/src/models.dart';
import 'package:vap_player_platform_interface/src/pigeon/vap_player_messages.g.dart';
import 'package:vap_player_platform_interface/src/vap_player_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('play forwards mapped request to host api', () async {
    final fakeHost = _FakeHostApi();
    final platform = PigeonVapPlayerPlatform(hostApi: fakeHost);

    await platform.play(
      const VapPlayRequest(
        viewId: 5,
        sourceType: VapSourceType.asset,
        source: 'assets/vap.mp4',
        repeatCount: -1,
        mute: true,
        contentMode: VapContentMode.aspectFit,
        fps: 30,
        frameEventsEnabled: true,
        tagValues: <String, String>{'[textUser]': 'Alice'},
      ),
    );

    final message = fakeHost.lastPlayRequest;
    expect(message, isNotNull);
    expect(message!.viewId, 5);
    expect(message.sourceType, VapSourceTypeMessage.asset);
    expect(message.source, 'assets/vap.mp4');
    expect(message.repeatCount, -1);
    expect(message.mute, true);
    expect(message.contentMode, VapContentModeMessage.aspectFit);
    expect(message.fps, 30);
    expect(message.frameEventsEnabled, true);
    expect(message.tagValues?['[textUser]'], 'Alice');
  });

  test('play maps network source type to pigeon enum', () async {
    final fakeHost = _FakeHostApi();
    final platform = PigeonVapPlayerPlatform(hostApi: fakeHost);

    await platform.play(
      const VapPlayRequest(
        viewId: 9,
        sourceType: VapSourceType.network,
        source: 'https://cdn.example.com/vap/net.mp4',
      ),
    );

    final message = fakeHost.lastPlayRequest;
    expect(message, isNotNull);
    expect(message!.sourceType, VapSourceTypeMessage.network);
    expect(message.source, 'https://cdn.example.com/vap/net.mp4');
  });

  test('resolveImage returns error when resolver is missing', () async {
    final platform = PigeonVapPlayerPlatform(hostApi: _FakeHostApi());

    final response = await platform.resolveImage(
      VapImageResolveRequestMessage(viewId: 100),
    );

    expect(response.imageBytes, isNull);
    expect(response.errorMessage, contains('No image resolver registered'));
  });

  test('resolveImage uses resolver and returns bytes', () async {
    final platform = PigeonVapPlayerPlatform(hostApi: _FakeHostApi());
    VapImageResolveRequest? capturedRequest;
    platform.setImageResolver(7, (VapImageResolveRequest request) async {
      capturedRequest = request;
      return Uint8List.fromList(<int>[9, 8, 7]);
    });

    final response = await platform.resolveImage(
      VapImageResolveRequestMessage(
        viewId: 7,
        resourceId: 'img-1',
        tag: '[sImg1]',
        type: 'img',
        loadType: 'net',
        width: 128,
        height: 64,
        url: 'https://example/avatar.png',
      ),
    );

    expect(response.errorMessage, isNull);
    expect(response.imageBytes, Uint8List.fromList(<int>[9, 8, 7]));
    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.resourceId, 'img-1');
    expect(capturedRequest!.tag, '[sImg1]');
    expect(capturedRequest!.width, 128);
    expect(capturedRequest!.height, 64);
  });

  test('resolveImage captures resolver exceptions as errorMessage', () async {
    final platform = PigeonVapPlayerPlatform(hostApi: _FakeHostApi());
    platform.setImageResolver(3, (VapImageResolveRequest request) async {
      throw StateError('boom');
    });

    final response = await platform.resolveImage(
      VapImageResolveRequestMessage(viewId: 3),
    );

    expect(response.imageBytes, isNull);
    expect(response.errorMessage, contains('boom'));
  });

  test('addPlaybackEvent and addClickEvent map nullable ids to -1', () async {
    final platform = PigeonVapPlayerPlatform(hostApi: _FakeHostApi());

    final playbackFuture = platform.playbackEvents.first;
    platform.addPlaybackEvent(VapPlaybackEventMessage());
    final playback = await playbackFuture;

    final clickFuture = platform.clickEvents.first;
    platform.addClickEvent(VapResourceClickEventMessage());
    final click = await clickFuture;

    expect(playback.viewId, -1);
    expect(playback.type, VapPlaybackEventType.failed);
    expect(click.viewId, -1);
  });

  test('network cache methods forward to host api', () async {
    final fakeHost = _FakeHostApi();
    final platform = PigeonVapPlayerPlatform(hostApi: fakeHost);

    fakeHost.networkCacheSizeBytes = 1234;
    final size = await platform.getNetworkCacheSizeBytes();
    await platform.clearNetworkCache();
    await platform.pruneNetworkCacheToBytes(512);

    expect(size, 1234);
    expect(fakeHost.clearNetworkCacheCalls, 1);
    expect(fakeHost.lastPruneMaxBytes, 512);
  });

  test('network auto-eviction max bytes methods forward to host api', () async {
    final fakeHost = _FakeHostApi();
    final platform = PigeonVapPlayerPlatform(hostApi: fakeHost);

    fakeHost.networkAutoEvictionMaxBytes = 8192;
    final value = await platform.getNetworkAutoEvictionMaxBytes();
    await platform.setNetworkAutoEvictionMaxBytes(4096);

    expect(value, 8192);
    expect(fakeHost.lastSetNetworkAutoEvictionMaxBytes, 4096);
  });
}

class _FakeHostApi extends VapHostApi {
  VapPlayRequestMessage? lastPlayRequest;
  int? lastStopViewId;
  (int viewId, bool mute)? lastMute;
  (int viewId, VapContentModeMessage mode)? lastContentMode;
  (int viewId, bool enabled)? lastFrameEventsEnabled;
  int? lastDisposeViewId;
  int networkCacheSizeBytes = 0;
  int clearNetworkCacheCalls = 0;
  int? lastPruneMaxBytes;
  int networkAutoEvictionMaxBytes = 0;
  int? lastSetNetworkAutoEvictionMaxBytes;

  @override
  Future<void> play(VapPlayRequestMessage request) async {
    lastPlayRequest = request;
  }

  @override
  Future<void> stop(int viewId) async {
    lastStopViewId = viewId;
  }

  @override
  Future<void> setMute(int viewId, bool mute) async {
    lastMute = (viewId, mute);
  }

  @override
  Future<void> setContentMode(int viewId, VapContentModeMessage mode) async {
    lastContentMode = (viewId, mode);
  }

  @override
  Future<void> setFrameEventsEnabled(int viewId, bool enabled) async {
    lastFrameEventsEnabled = (viewId, enabled);
  }

  @override
  Future<void> dispose(int viewId) async {
    lastDisposeViewId = viewId;
  }

  @override
  Future<int> getNetworkCacheSizeBytes() async {
    return networkCacheSizeBytes;
  }

  @override
  Future<void> clearNetworkCache() async {
    clearNetworkCacheCalls += 1;
  }

  @override
  Future<void> pruneNetworkCacheToBytes(int maxBytes) async {
    lastPruneMaxBytes = maxBytes;
  }

  @override
  Future<int> getNetworkAutoEvictionMaxBytes() async {
    return networkAutoEvictionMaxBytes;
  }

  @override
  Future<void> setNetworkAutoEvictionMaxBytes(int maxBytes) async {
    lastSetNetworkAutoEvictionMaxBytes = maxBytes;
  }
}
