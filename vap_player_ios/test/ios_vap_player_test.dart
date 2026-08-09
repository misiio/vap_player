import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vap_player_ios/src/ios_vap_player.dart';
import 'package:vap_player_ios/src/messages.g.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePluginApi pluginApi;
  late _FakeInstanceApi instanceApi;
  late StreamController<PlatformVapEvent> eventController;
  late IosVapPlayer player;

  setUp(() {
    pluginApi = _FakePluginApi();
    instanceApi = _FakeInstanceApi();
    eventController = StreamController<PlatformVapEvent>();
    player = IosVapPlayer(
      pluginApi: pluginApi,
      playerApiProvider: (int playerId) => instanceApi,
      eventStreamProvider: (String instanceName) => eventController.stream,
    );
  });

  test('texture view requests fall back to a platform view', () async {
    final int playerId = await player.create(
      const VapCreationOptions(viewType: VapViewType.textureView),
    );
    expect(playerId, 5);
    final Widget view = player.buildViewWithOptions(
      const VapViewOptions(playerId: 5),
    );
    expect(view, isA<UiKitView>());
  });

  test('play keeps the native renderer in scaleToFill mode', () async {
    final int playerId = await player.create(const VapCreationOptions());
    await player.play(
      playerId,
      const VapPlayOptions(
        path: '/x/y.mp4',
        repeatCount: 2,
        scaleType: VapScaleType.centerCrop,
        enableOldVersion: true,
      ),
    );

    final PlatformPlayOptions options = instanceApi.lastPlayOptions!;
    expect(options.path, '/x/y.mp4');
    expect(options.repeatCount, 2);
    expect(options.contentMode, PlatformContentMode.scaleToFill);
    expect(options.enableOldVersion, true);
  });

  test('pause and resume are supported and forwarded', () async {
    final int playerId = await player.create(const VapCreationOptions());
    expect(player.isPauseResumeSupported, true);
    await player.pause(playerId);
    await player.resume(playerId);
    expect(instanceApi.calls, <String>['pause', 'resume']);
  });

  test('completed event is mapped', () async {
    final int playerId = await player.create(const VapCreationOptions());
    final Future<VapEvent> firstEvent = player.vapEventsFor(playerId).first;
    eventController.add(CompletedEvent());
    expect(await firstEvent, isA<VapCompletedEvent>());
  });

  test('parse config failure is mapped', () async {
    final int playerId = await player.create(const VapCreationOptions());
    final Future<VapEvent> firstEvent = player.vapEventsFor(playerId).first;
    eventController.add(
      FailedEvent(errorType: 10005, errorMsg: '0x5 parse config fail'),
    );

    final VapErrorEvent event = await firstEvent as VapErrorEvent;
    expect(event.code, 10005);
    expect(event.message, '0x5 parse config fail');
  });
}

class _FakePluginApi extends IosVapPlayerApi {
  @override
  Future<void> initialize() async {}

  @override
  Future<int> create(PlatformCreationOptions options) async {
    return 5;
  }

  @override
  Future<void> dispose(int playerId) async {}
}

class _FakeInstanceApi extends VapPlayerInstanceApi {
  PlatformPlayOptions? lastPlayOptions;
  final List<String> calls = <String>[];

  @override
  Future<void> play(PlatformPlayOptions options) async {
    lastPlayOptions = options;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
  }

  @override
  Future<void> setMute(bool mute) async {}

  @override
  Future<void> setRepeatCount(int repeatCount) async {}

  @override
  Future<void> setHasResourceDelegate(bool hasDelegate) async {}
}
