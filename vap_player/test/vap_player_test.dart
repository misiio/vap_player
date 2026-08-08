import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vap_player/flutter_vap_player.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVapPlayerPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeVapPlayerPlatform();
    VapPlayerPlatform.instance = fakePlatform;
  });

  VapPlayerController createFileController({VapPlayerOptions? options}) {
    // A file source avoids asset/network materialization in tests; the
    // file is never opened, only its path is forwarded.
    return VapPlayerController.file(File('/tmp/fake.mp4'), options: options);
  }

  group('VapPlayerController', () {
    test('initialize creates a player and subscribes to events', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      expect(controller.playerId, 1);
      expect(controller.value.isInitialized, true);
      expect(fakePlatform.calls, contains('create'));
      expect(fakePlatform.creationOptions!.viewType, VapViewType.platformView);
    });

    test('initialize forwards view type and frame events flag', () async {
      final VapPlayerController controller = createFileController(
        options: const VapPlayerOptions(
          viewType: VapViewType.textureView,
          enableFrameEvents: true,
        ),
      );
      await controller.initialize();

      expect(fakePlatform.creationOptions!.viewType, VapViewType.textureView);
      expect(fakePlatform.creationOptions!.enableFrameEvents, true);
    });

    test('play sends options to the platform', () async {
      final VapPlayerController controller = createFileController(
        options: const VapPlayerOptions(
          repeatCount: 2,
          mute: true,
          scaleType: VapScaleType.centerCrop,
        ),
      );
      await controller.initialize();
      await controller.play();

      final VapPlayOptions options = fakePlatform.lastPlayOptions!;
      expect(options.path, '/tmp/fake.mp4');
      expect(options.repeatCount, 2);
      expect(options.mute, true);
      expect(options.scaleType, VapScaleType.centerCrop);
    });

    test('play before initialize throws', () async {
      final VapPlayerController controller = createFileController();
      expect(() => controller.play(), throwsStateError);
    });

    test('config ready event populates value', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      fakePlatform.sendEvent(
        controller.playerId,
        const VapConfigReadyEvent(
          width: 750,
          height: 1250,
          videoWidth: 900,
          videoHeight: 1280,
          frameCount: 100,
          fps: 25,
          isMix: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.value.size, const Size(750, 1250));
      expect(controller.value.videoSize, const Size(900, 1280));
      expect(controller.value.frameCount, 100);
      expect(controller.value.fps, 25);
      expect(controller.value.isMix, true);
      expect(controller.value.aspectRatio, 750 / 1250);
    });

    test('start and completion events update playing state', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      fakePlatform.sendEvent(controller.playerId, const VapStartedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isPlaying, true);
      expect(controller.value.isCompleted, false);

      fakePlatform.sendEvent(controller.playerId, const VapCompletedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isPlaying, false);
      expect(controller.value.isCompleted, true);
    });

    test('error event sets errorDescription', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      fakePlatform.sendEvent(
        controller.playerId,
        const VapErrorEvent(code: 10004, message: 'decode failed'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.value.hasError, true);
      expect(controller.value.errorDescription, 'decode failed');

      // A successful restart clears the error.
      fakePlatform.sendEvent(controller.playerId, const VapStartedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.hasError, false);
    });

    test('old-version failure remains an error after native cleanup', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      fakePlatform.sendEvent(
        controller.playerId,
        const VapErrorEvent(code: 10005, message: '0x5 parse config fail'),
      );
      fakePlatform.sendEvent(controller.playerId, const VapCompletedEvent());
      fakePlatform.sendEvent(controller.playerId, const VapDestroyedEvent());
      await Future<void>.delayed(Duration.zero);

      expect(controller.value.hasError, true);
      expect(controller.value.errorDescription, '0x5 parse config fail');
      expect(controller.value.isCompleted, true);
      expect(controller.value.isPlaying, false);
    });

    test('frame events update currentFrame', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      fakePlatform.sendEvent(controller.playerId, const VapFrameEvent(42));
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.currentFrame, 42);
    });

    test('resource click event invokes callback', () async {
      VapResource? clicked;
      final VapPlayerController controller = createFileController(
        options: VapPlayerOptions(
          onResourceClick: (VapResource resource) => clicked = resource,
        ),
      );
      await controller.initialize();

      const VapResource resource = VapResource(
        id: '1',
        type: VapResourceType.image,
        tag: '[sImg1]',
      );
      fakePlatform.sendEvent(
        controller.playerId,
        const VapResourceClickEvent(resource),
      );
      await Future<void>.delayed(Duration.zero);
      expect(clicked, resource);
    });

    test('resource delegate is registered and cleared', () async {
      final VapPlayerController controller = createFileController(
        options: VapPlayerOptions(
          resourceDelegate: VapResourceDelegate(
            resolveText: (VapResource resource) async => 'hi',
          ),
        ),
      );
      await controller.initialize();
      expect(fakePlatform.resourceDelegates[controller.playerId], isNotNull);

      final int playerId = controller.playerId;
      await controller.dispose();
      expect(fakePlatform.resourceDelegates[playerId], isNull);
    });

    test('canPause reflects platform support', () async {
      fakePlatform.pauseResumeSupported = true;
      final VapPlayerController controller = createFileController();
      await controller.initialize();
      expect(controller.value.canPause, true);
    });

    test('control methods forward to the platform', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      await controller.stop();
      await controller.setMute(true);
      await controller.setRepeatCount(-1);

      expect(
        fakePlatform.calls,
        containsAllInOrder(<String>['create', 'stop', 'setMute']),
      );
      expect(fakePlatform.lastMute, true);
      expect(fakePlatform.lastRepeatCount, -1);
    });

    test('dispose disposes the platform player', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();
      final int playerId = controller.playerId;

      await controller.dispose();
      expect(fakePlatform.disposedPlayers, contains(playerId));
      expect(() => controller.play(), throwsStateError);
    });
  });

  group('VapPlayerOptions', () {
    test('loop true maps to repeatCount -1', () {
      expect(const VapPlayerOptions(loop: true).repeatCount, -1);
    });

    test('loop false maps to repeatCount 0', () {
      expect(const VapPlayerOptions(loop: false).repeatCount, 0);
    });

    test('repeatCount takes precedence when both are provided', () {
      expect(const VapPlayerOptions(loop: true, repeatCount: 5).repeatCount, 5);
    });

    test('defaults to repeatCount 0 when neither is provided', () {
      expect(const VapPlayerOptions().repeatCount, 0);
    });
  });

  group('VapPlayer widget', () {
    testWidgets('passes scaleType and size to the platform view', (
      WidgetTester tester,
    ) async {
      final VapPlayerController controller = createFileController(
        options: const VapPlayerOptions(scaleType: VapScaleType.fitCenter),
      );
      await controller.initialize();

      await tester.pumpWidget(VapPlayer(controller));
      VapViewOptions options = fakePlatform.lastViewOptions!;
      expect(options.playerId, controller.playerId);
      expect(options.scaleType, VapScaleType.fitCenter);
      expect(options.size, Size.zero);

      // Once the config is parsed the widget rebuilds with the size.
      fakePlatform.sendEvent(
        controller.playerId,
        const VapConfigReadyEvent(
          width: 750,
          height: 1250,
          videoWidth: 900,
          videoHeight: 1280,
          frameCount: 100,
          fps: 25,
          isMix: false,
        ),
      );
      // One pump delivers the stream event, the next rebuilds the widget.
      await tester.pump();
      await tester.pump();
      options = fakePlatform.lastViewOptions!;
      expect(options.size, const Size(750, 1250));

      // dispose() awaits real async work, which deadlocks inside the
      // FakeAsync test zone.
      await tester.runAsync(controller.dispose);
    });
  });
}

class FakeVapPlayerPlatform extends VapPlayerPlatform {
  final List<String> calls = <String>[];
  final Map<int, StreamController<VapEvent>> eventControllers =
      <int, StreamController<VapEvent>>{};
  final Map<int, VapResourceDelegate?> resourceDelegates =
      <int, VapResourceDelegate?>{};
  final List<int> disposedPlayers = <int>[];

  VapCreationOptions? creationOptions;
  VapPlayOptions? lastPlayOptions;
  VapViewOptions? lastViewOptions;
  bool? lastMute;
  int? lastRepeatCount;
  bool pauseResumeSupported = false;
  int nextPlayerId = 1;

  void sendEvent(int playerId, VapEvent event) {
    eventControllers[playerId]!.add(event);
  }

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Future<int> create(VapCreationOptions options) async {
    calls.add('create');
    creationOptions = options;
    final int playerId = nextPlayerId++;
    eventControllers[playerId] = StreamController<VapEvent>.broadcast();
    return playerId;
  }

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    disposedPlayers.add(playerId);
  }

  @override
  Future<void> play(int playerId, VapPlayOptions options) async {
    calls.add('play');
    lastPlayOptions = options;
  }

  @override
  Future<void> stop(int playerId) async {
    calls.add('stop');
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
  }

  @override
  Future<void> resume(int playerId) async {
    calls.add('resume');
  }

  @override
  bool get isPauseResumeSupported => pauseResumeSupported;

  @override
  Future<void> setMute(int playerId, bool mute) async {
    calls.add('setMute');
    lastMute = mute;
  }

  @override
  Future<void> setRepeatCount(int playerId, int repeatCount) async {
    calls.add('setRepeatCount');
    lastRepeatCount = repeatCount;
  }

  @override
  void setResourceDelegate(int playerId, VapResourceDelegate? delegate) {
    calls.add('setResourceDelegate');
    resourceDelegates[playerId] = delegate;
  }

  @override
  Stream<VapEvent> vapEventsFor(int playerId) {
    return eventControllers[playerId]!.stream;
  }

  @override
  Widget buildViewWithOptions(VapViewOptions options) {
    lastViewOptions = options;
    return const SizedBox();
  }
}
