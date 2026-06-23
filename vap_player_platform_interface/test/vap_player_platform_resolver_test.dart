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
      const VapPlatformPlayRequest(
        viewId: 5,
        sourceType: VapPlatformSourceType.asset,
        source: 'assets/vap.mp4',
        assetPackage: 'demo',
        loop: true,
        muted: true,
        contentMode: VapPlatformContentMode.aspectFit,
        frameEvents: true,
        tagValues: <String, String>{'[textUser]': 'Alice'},
      ),
    );

    final message = fakeHost.lastPlayRequest;
    expect(message, isNotNull);
    expect(message!.viewId, 5);
    expect(message.sourceType, VapSourceTypeMessage.asset);
    expect(message.source, 'assets/vap.mp4');
    expect(message.assetPackage, 'demo');
    expect(message.loop, true);
    expect(message.muted, true);
    expect(message.contentMode, VapContentModeMessage.aspectFit);
    expect(message.frameEvents, true);
    expect(message.tagValues?['[textUser]'], 'Alice');
  });

  test('play maps network source type to pigeon enum', () async {
    final fakeHost = _FakeHostApi();
    final platform = PigeonVapPlayerPlatform(hostApi: fakeHost);

    await platform.play(
      const VapPlatformPlayRequest(
        viewId: 9,
        sourceType: VapPlatformSourceType.network,
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
    VapPlatformImageResolveRequest? capturedRequest;
    platform.setImageResolver(7, (
      VapPlatformImageResolveRequest request,
    ) async {
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
    platform.setImageResolver(3, (
      VapPlatformImageResolveRequest request,
    ) async {
      throw StateError('boom');
    });

    final response = await platform.resolveImage(
      VapImageResolveRequestMessage(viewId: 3),
    );

    expect(response.imageBytes, isNull);
    expect(response.errorMessage, contains('boom'));
  });

  test('addEvent maps nullable ids and payloads', () async {
    final platform = PigeonVapPlayerPlatform(hostApi: _FakeHostApi());

    final playbackFuture = platform.events.first;
    platform.addEvent(VapEventMessage());
    final playback = await playbackFuture;

    expect(playback, isA<VapPlatformPlaybackEvent>());
    expect(playback.viewId, -1);
    expect(
      (playback as VapPlatformPlaybackEvent).type,
      VapPlatformPlaybackEventType.failed,
    );

    final clickFuture = platform.events.first;
    platform.addEvent(
      VapEventMessage(
        kind: VapEventKindMessage.resourceClick,
        tag: 'tap',
        resourceWidth: 10,
      ),
    );
    final click = await clickFuture;

    expect(click, isA<VapPlatformResourceClickEvent>());
    expect(click.viewId, -1);
    expect((click as VapPlatformResourceClickEvent).tag, 'tap');
    expect(click.width, 10);
  });

  test('network cache methods forward to host api', () async {
    final fakeHost = _FakeHostApi();
    final platform = PigeonVapPlayerPlatform(hostApi: fakeHost);

    fakeHost.cacheInfo = VapNetworkCacheInfoMessage(
      sizeBytes: 1234,
      maxBytes: 8192,
    );
    final info = await platform.getNetworkCacheInfo();
    await platform.clearNetworkCache();
    await platform.setNetworkCacheMaxBytes(4096);

    expect(info.sizeBytes, 1234);
    expect(info.maxBytes, 8192);
    expect(fakeHost.clearNetworkCacheCalls, 1);
    expect(fakeHost.lastSetNetworkCacheMaxBytes, 4096);
  });
}

class _FakeHostApi extends VapHostApi {
  VapPlayRequestMessage? lastPlayRequest;
  int? lastStopViewId;
  int? lastDisposeViewId;
  VapNetworkCacheInfoMessage cacheInfo = VapNetworkCacheInfoMessage(
    sizeBytes: 0,
    maxBytes: 0,
  );
  int clearNetworkCacheCalls = 0;
  int? lastSetNetworkCacheMaxBytes;

  @override
  Future<void> play(VapPlayRequestMessage request) async {
    lastPlayRequest = request;
  }

  @override
  Future<void> stop(int viewId) async {
    lastStopViewId = viewId;
  }

  @override
  Future<void> dispose(int viewId) async {
    lastDisposeViewId = viewId;
  }

  @override
  Future<VapNetworkCacheInfoMessage> getNetworkCacheInfo() async {
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
