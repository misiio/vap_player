import 'dart:async';
import 'dart:convert';
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
    // A file source avoids asset/network materialization in tests. The file
    // does not exist, so initialize() finds no metadata to read and the
    // player's size stays unknown until a config event arrives.
    return VapPlayerController.file(File('/tmp/fake.mp4'), options: options);
  }

  Size rendererSize(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('renderer')));

  /// Pumps a player whose animation is 100x200 into a 300x200 viewport.
  ///
  /// The source is a real mp4 fixture, so the size is known before the first
  /// build — exactly as it is in an app.
  Future<VapPlayerController> pumpSizedPlayer(
    WidgetTester tester, {
    required VapScaleType scaleType,
    Widget Function(Widget player)? wrap,
  }) async {
    final Directory tempDir = Directory.systemTemp.createTempSync('vap');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final File file = File('${tempDir.path}/animation.mp4')
      ..writeAsBytesSync(
        vapcFixture(
          '{"info":{"v":2,"f":0,"w":100,"h":200,"videoW":200,'
          '"videoH":200,"fps":0,"isVapx":0}}',
        ),
      );

    fakePlatform.view = const SizedBox.expand(key: Key('renderer'));
    final VapPlayerController controller = VapPlayerController.file(
      file,
      options: VapPlayerOptions(scaleType: scaleType),
    );
    // initialize() reads the mp4 header, which is real I/O that the FakeAsync
    // test zone never pumps.
    await tester.runAsync(controller.initialize);
    expect(controller.value.size, const Size(100, 200));

    final Widget player = VapPlayer(controller);
    await tester.pumpWidget(
      wrap?.call(player) ??
          Center(child: SizedBox(width: 300, height: 200, child: player)),
    );
    return controller;
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

    test('initialize reads the animation size from the mp4', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('vap');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final File file = File('${tempDir.path}/animation.mp4')
        ..writeAsBytesSync(
          vapcFixture(
            '{"info":{"v":2,"f":80,"w":736,"h":576,"videoW":752,'
            '"videoH":880,"fps":25,"isVapx":1}}',
          ),
        );

      final VapPlayerController controller = VapPlayerController.file(file);
      await controller.initialize();

      // Available before play(), so the widget can lay the animation out
      // correctly from its first frame.
      expect(controller.value.size, const Size(736, 576));
      expect(controller.value.videoSize, const Size(752, 880));
      expect(controller.value.frameCount, 80);
      expect(controller.value.fps, 25);
      expect(controller.value.isMix, true);
      expect(controller.value.aspectRatio, closeTo(736 / 576, 0.0001));
    });

    test('initialize keeps the size unknown for an unreadable source', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      expect(controller.value.size, Size.zero);
      expect(controller.value.isInitialized, true);
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

    test('events forwards every typed event unchanged', () async {
      final VapPlayerController controller = createFileController();
      final Future<List<VapEvent>> receivedFuture = controller.events
          .take(7)
          .toList();
      await controller.initialize();

      const VapConfigReadyEvent config = VapConfigReadyEvent(
        width: 750,
        height: 1250,
        videoWidth: 900,
        videoHeight: 1280,
        frameCount: 100,
        fps: 25,
        isMix: true,
      );
      const VapStartedEvent started = VapStartedEvent();
      const VapFrameEvent frame = VapFrameEvent(42);
      const VapCompletedEvent completed = VapCompletedEvent();
      const VapDestroyedEvent destroyed = VapDestroyedEvent();
      const VapErrorEvent error = VapErrorEvent(
        code: 10004,
        message: 'decode failed',
      );
      const VapResourceClickEvent click = VapResourceClickEvent(
        VapResource(id: '1', type: VapResourceType.image, tag: '[sImg1]'),
      );
      const List<VapEvent> sent = <VapEvent>[
        config,
        started,
        frame,
        completed,
        destroyed,
        error,
        click,
      ];

      for (final VapEvent event in sent) {
        fakePlatform.sendEvent(controller.playerId, event);
      }

      expect(await receivedFuture, orderedEquals(sent));
    });

    test('events publishes after updating controller state', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      final Future<bool> wasPlaying = controller.events
          .where((VapEvent event) => event is VapStartedEvent)
          .map((_) => controller.value.isPlaying)
          .first;
      fakePlatform.sendEvent(controller.playerId, const VapStartedEvent());

      expect(await wasPlaying, true);
    });

    test('events is broadcast to multiple listeners', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      final Future<VapEvent> firstListener = controller.events.first;
      final Future<VapEvent> secondListener = controller.events.first;
      const VapCompletedEvent event = VapCompletedEvent();
      fakePlatform.sendEvent(controller.playerId, event);

      expect(await firstListener, same(event));
      expect(await secondListener, same(event));
    });

    test('platform stream errors update state and reach events', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();

      final Completer<(Object, StackTrace)> receivedError =
          Completer<(Object, StackTrace)>();
      final StreamSubscription<VapEvent> subscription = controller.events
          .listen(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              receivedError.complete((error, stackTrace));
            },
          );
      final StateError error = StateError('event channel failed');
      final StackTrace stackTrace = StackTrace.current;
      fakePlatform.sendError(controller.playerId, error, stackTrace);

      final (Object forwardedError, StackTrace forwardedStackTrace) =
          await receivedError.future;
      expect(forwardedError, same(error));
      expect(forwardedStackTrace, same(stackTrace));
      expect(controller.value.errorDescription, error.toString());
      await subscription.cancel();
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
      final Future<VapResourceClickEvent> streamedClick = controller.events
          .where((VapEvent event) => event is VapResourceClickEvent)
          .cast<VapResourceClickEvent>()
          .first;
      fakePlatform.sendEvent(
        controller.playerId,
        const VapResourceClickEvent(resource),
      );
      await Future<void>.delayed(Duration.zero);
      expect(clicked, resource);
      expect((await streamedClick).resource, resource);
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
      final Future<void> eventsDone = controller.events.drain<void>();

      await controller.dispose();
      await eventsDone;
      expect(fakePlatform.disposedPlayers, contains(playerId));
      expect(() => controller.play(), throwsStateError);

      fakePlatform.sendEvent(playerId, const VapStartedEvent());
    });

    test('dispose closes events when native teardown fails', () async {
      final VapPlayerController controller = createFileController();
      await controller.initialize();
      final Future<void> eventsDone = controller.events.drain<void>();
      fakePlatform.disposeError = StateError('dispose failed');

      await expectLater(controller.dispose(), throwsStateError);
      await eventsDone;
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
      await tester.runAsync(controller.initialize);

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

    testWidgets('fitXY leaves the renderer unwrapped', (
      WidgetTester tester,
    ) async {
      final VapPlayerController controller = await pumpSizedPlayer(
        tester,
        scaleType: VapScaleType.fitXY,
      );

      // Clipping a platform view is expensive, so nothing that fills its box
      // should be wrapped in a clip or an overflow box.
      expect(find.byType(ClipRect), findsNothing);
      expect(find.byType(OverflowBox), findsNothing);
      expect(rendererSize(tester), const Size(300, 200));
      await tester.runAsync(controller.dispose);
    });

    testWidgets('fitCenter contains the animation without clipping', (
      WidgetTester tester,
    ) async {
      final VapPlayerController controller = await pumpSizedPlayer(
        tester,
        scaleType: VapScaleType.fitCenter,
      );

      // A contained animation never overflows, so it needs no clip.
      expect(find.byType(ClipRect), findsNothing);
      expect(rendererSize(tester), const Size(100, 200));
      await tester.runAsync(controller.dispose);
    });

    testWidgets('centerCrop covers the viewport inside a clip', (
      WidgetTester tester,
    ) async {
      final VapPlayerController controller = await pumpSizedPlayer(
        tester,
        scaleType: VapScaleType.centerCrop,
      );

      expect(find.byType(ClipRect), findsOneWidget);
      expect(rendererSize(tester), const Size(300, 600));
      await tester.runAsync(controller.dispose);
    });

    testWidgets('centerCrop falls back to containing when unbounded', (
      WidgetTester tester,
    ) async {
      final VapPlayerController controller = await pumpSizedPlayer(
        tester,
        scaleType: VapScaleType.centerCrop,
        // A scroll view gives its children unbounded height.
        wrap: (Widget player) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: ListView(shrinkWrap: true, children: <Widget>[player]),
            ),
          ),
        ),
      );

      // Covering is undefined without a viewport to cover; containing keeps
      // the aspect ratio instead of asserting on an infinite size.
      expect(tester.takeException(), isNull);
      expect(rendererSize(tester), const Size(300, 600));
      await tester.runAsync(controller.dispose);
    });

    testWidgets('resizes the renderer in place when the size arrives', (
      WidgetTester tester,
    ) async {
      final GlobalKey<_CountingRendererState> rendererKey =
          GlobalKey<_CountingRendererState>();
      fakePlatform.view = _CountingRenderer(key: rendererKey);
      final VapPlayerController controller = createFileController(
        options: const VapPlayerOptions(scaleType: VapScaleType.fitCenter),
      );
      await tester.runAsync(controller.initialize);

      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: VapPlayer(controller),
          ),
        ),
      );
      final _CountingRendererState originalState = rendererKey.currentState!;
      expect(
        tester.getSize(find.byType(_CountingRenderer)),
        const Size(300, 200),
      );

      fakePlatform.sendEvent(
        controller.playerId,
        const VapConfigReadyEvent(
          width: 100,
          height: 200,
          videoWidth: 200,
          videoHeight: 200,
          frameCount: 0,
          fps: 0,
          isMix: false,
        ),
      );
      await tester.pump();
      await tester.pump();

      // Replacing the renderer here would tear down a live platform view.
      expect(rendererKey.currentState, same(originalState));
      expect(
        tester.getSize(find.byType(_CountingRenderer)),
        const Size(100, 200),
      );
      await tester.runAsync(controller.dispose);
    });
  });
}

/// A minimal mp4 carrying a top-level `vapc` box holding [json].
List<int> vapcFixture(String json) {
  List<int> box(String type, List<int> payload) => <int>[
    ...<int>[
      payload.length + 8 >> 24 & 0xFF,
      payload.length + 8 >> 16 & 0xFF,
      payload.length + 8 >> 8 & 0xFF,
      payload.length + 8 & 0xFF,
    ],
    ...ascii.encode(type),
    ...payload,
  ];
  return <int>[
    ...box('ftyp', ascii.encode('isom')),
    ...box('vapc', utf8.encode(json)),
  ];
}

class _CountingRenderer extends StatefulWidget {
  const _CountingRenderer({super.key});

  @override
  State<_CountingRenderer> createState() => _CountingRendererState();
}

class _CountingRendererState extends State<_CountingRenderer> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
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
  Object? disposeError;
  int nextPlayerId = 1;
  Widget view = const SizedBox();

  void sendEvent(int playerId, VapEvent event) {
    eventControllers[playerId]!.add(event);
  }

  void sendError(int playerId, Object error, StackTrace stackTrace) {
    eventControllers[playerId]!.addError(error, stackTrace);
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
    final Object? error = disposeError;
    if (error != null) {
      throw error;
    }
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
    return view;
  }
}
