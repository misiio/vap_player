import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vap_player_android/src/android_vap_player.dart';
import 'package:vap_player_android/src/messages.g.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePluginApi pluginApi;
  late _FakeInstanceApi instanceApi;
  late StreamController<PlatformVapEvent> eventController;
  late AndroidVapPlayer player;

  setUp(() {
    pluginApi = _FakePluginApi();
    instanceApi = _FakeInstanceApi();
    eventController = StreamController<PlatformVapEvent>();
    player = AndroidVapPlayer(
      pluginApi: pluginApi,
      playerApiProvider: (int playerId) => instanceApi,
      eventStreamProvider: (String instanceName) => eventController.stream,
    );
  });

  test(
    'create for texture view returns playerId and builds a Texture',
    () async {
      final int playerId = await player.create(
        const VapCreationOptions(viewType: VapViewType.textureView),
      );
      expect(playerId, 7);
      expect(pluginApi.lastOptions!.viewType, PlatformVapViewType.textureView);

      final Widget view = player.buildViewWithOptions(
        const VapViewOptions(playerId: 7),
      );
      expect(view, isA<Texture>());
      expect((view as Texture).textureId, 42);
    },
  );

  test(
    'texture view applies fitCenter and centerCrop with FittedBox',
    () async {
      final int playerId = await player.create(
        const VapCreationOptions(viewType: VapViewType.textureView),
      );

      final Widget fitCenter = player.buildViewWithOptions(
        VapViewOptions(
          playerId: playerId,
          scaleType: VapScaleType.fitCenter,
          size: const Size(750, 1250),
        ),
      );
      expect(fitCenter, isA<FittedBox>());
      expect((fitCenter as FittedBox).fit, BoxFit.contain);
      final SizedBox box = fitCenter.child! as SizedBox;
      expect(box.width, 750);
      expect(box.height, 1250);
      expect(box.child, isA<Texture>());

      final Widget centerCrop = player.buildViewWithOptions(
        VapViewOptions(
          playerId: playerId,
          scaleType: VapScaleType.centerCrop,
          size: const Size(750, 1250),
        ),
      );
      expect((centerCrop as FittedBox).fit, BoxFit.cover);
      expect(centerCrop.clipBehavior, Clip.hardEdge);
    },
  );

  test('texture view stays unfitted for fitXY or unknown size', () async {
    final int playerId = await player.create(
      const VapCreationOptions(viewType: VapViewType.textureView),
    );

    expect(
      player.buildViewWithOptions(
        VapViewOptions(
          playerId: playerId,
          scaleType: VapScaleType.fitXY,
          size: const Size(750, 1250),
        ),
      ),
      isA<Texture>(),
    );
    expect(
      player.buildViewWithOptions(
        VapViewOptions(playerId: playerId, scaleType: VapScaleType.fitCenter),
      ),
      isA<Texture>(),
    );
    expect(
      player.buildViewWithOptions(
        VapViewOptions(
          playerId: playerId,
          scaleType: VapScaleType.fitCenter,
          size: Size.zero,
        ),
      ),
      isA<Texture>(),
    );
  });

  test('create for platform view returns playerId', () async {
    final int playerId = await player.create(
      const VapCreationOptions(viewType: VapViewType.platformView),
    );
    expect(playerId, 3);
    expect(pluginApi.lastOptions!.viewType, PlatformVapViewType.platformView);
    final Widget view = player.buildViewWithOptions(
      const VapViewOptions(playerId: 3),
    );
    expect(view, isNot(isA<Texture>()));
  });

  test('play maps options to pigeon', () async {
    final int playerId = await player.create(const VapCreationOptions());
    await player.play(
      playerId,
      const VapPlayOptions(
        path: '/x/y.mp4',
        repeatCount: -1,
        mute: true,
        scaleType: VapScaleType.fitCenter,
        fps: 30,
        enableOldVersion: true,
      ),
    );

    final PlatformPlayOptions options = instanceApi.lastPlayOptions!;
    expect(options.path, '/x/y.mp4');
    expect(options.repeatCount, -1);
    expect(options.mute, true);
    expect(options.scaleType, PlatformScaleType.fitCenter);
    expect(options.fps, 30);
    expect(options.enableOldVersion, true);
  });

  test('pause and resume are unsupported', () async {
    final int playerId = await player.create(const VapCreationOptions());
    expect(player.isPauseResumeSupported, false);
    expect(() => player.pause(playerId), throwsUnsupportedError);
    expect(() => player.resume(playerId), throwsUnsupportedError);
  });

  test('events are mapped to platform-interface events', () async {
    final int playerId = await player.create(const VapCreationOptions());
    final Future<List<VapEvent>> eventsFuture = player
        .vapEventsFor(playerId)
        .take(5)
        .toList();

    eventController
      ..add(
        ConfigReadyEvent(
          width: 750,
          height: 1250,
          videoWidth: 900,
          videoHeight: 1280,
          frameCount: 100,
          fps: 25,
          isMix: true,
        ),
      )
      ..add(StartedEvent())
      ..add(FrameRenderedEvent(frameIndex: 9))
      ..add(FailedEvent(errorType: 10004, errorMsg: 'boom'))
      ..add(
        ResourceClickedEvent(
          resource: PlatformVapResource(
            id: '1',
            type: PlatformResourceType.image,
            tag: '[sImg1]',
          ),
        ),
      );

    final List<VapEvent> events = await eventsFuture;
    expect(events[0], isA<VapConfigReadyEvent>());
    final VapConfigReadyEvent config = events[0] as VapConfigReadyEvent;
    expect(config.width, 750);
    expect(config.frameCount, 100);
    expect(config.isMix, true);
    expect(events[1], isA<VapStartedEvent>());
    expect((events[2] as VapFrameEvent).frameIndex, 9);
    final VapErrorEvent error = events[3] as VapErrorEvent;
    expect(error.code, 10004);
    expect(error.message, 'boom');
    final VapResourceClickEvent click = events[4] as VapResourceClickEvent;
    expect(click.resource.tag, '[sImg1]');
    expect(click.resource.type, VapResourceType.image);
  });

  test('dispose forwards to the plugin api', () async {
    final int playerId = await player.create(const VapCreationOptions());
    await player.dispose(playerId);
    expect(pluginApi.disposed, contains(playerId));
  });
}

class _FakePluginApi extends AndroidVapPlayerApi {
  PlatformCreationOptions? lastOptions;
  final List<int> disposed = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<int> createForPlatformView(PlatformCreationOptions options) async {
    lastOptions = options;
    return 3;
  }

  @override
  Future<TexturePlayerIds> createForTextureView(
    PlatformCreationOptions options,
  ) async {
    lastOptions = options;
    return TexturePlayerIds(playerId: 7, textureId: 42);
  }

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }
}

class _FakeInstanceApi extends VapPlayerInstanceApi {
  PlatformPlayOptions? lastPlayOptions;

  @override
  Future<void> play(PlatformPlayOptions options) async {
    lastPlayOptions = options;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> setMute(bool mute) async {}

  @override
  Future<void> setRepeatCount(int repeatCount) async {}

  @override
  Future<void> setHasResourceDelegate(bool hasDelegate) async {}
}
