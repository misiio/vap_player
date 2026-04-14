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
}

class _FakeHostApi extends VapHostApi {
  VapPlayRequestMessage? lastPlayRequest;
  int? lastStopViewId;
  (int viewId, bool mute)? lastMute;
  (int viewId, VapContentModeMessage mode)? lastContentMode;
  (int viewId, bool enabled)? lastFrameEventsEnabled;
  int? lastDisposeViewId;

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
}
