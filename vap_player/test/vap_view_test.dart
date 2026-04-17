import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vap_player/src/vap_controller.dart';
import 'package:flutter_vap_player/src/vap_view.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVapPlayerPlatform fakePlatform;
  final VapPlayerPlatform previousPlatform = VapPlayerPlatform.instance;

  setUp(() {
    fakePlatform = FakeVapPlayerPlatform();
    VapPlayerPlatform.instance = fakePlatform;
  });

  tearDown(() {
    VapPlayerPlatform.instance = previousPlatform;
  });

  test('handoff detaches old controller and attaches new controller', () async {
    final oldController = VapController(platform: fakePlatform);
    final newController = VapController(platform: fakePlatform);
    final List<VapPlaybackEvent> oldEvents = <VapPlaybackEvent>[];
    final List<VapPlaybackEvent> newEvents = <VapPlaybackEvent>[];
    final oldSub = oldController.playbackEvents.listen(oldEvents.add);
    final newSub = newController.playbackEvents.listen(newEvents.add);

    oldController.attach(41);
    oldController.setImageResolver((VapImageResolveRequest request) async {
      return null;
    });
    expect(fakePlatform.hasResolverForView(41), true);

    handoffVapViewController(
      oldController: oldController,
      newController: newController,
      viewId: 41,
    );

    expect(oldController.viewId, isNull);
    expect(newController.viewId, 41);
    expect(fakePlatform.hasResolverForView(41), false);
    expect(fakePlatform.disposeCalls, isEmpty);

    fakePlatform.emitPlayback(
      const VapPlaybackEvent(viewId: 41, type: VapPlaybackEventType.started),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(oldEvents, isEmpty);
    expect(newEvents.length, 1);
    expect(newEvents.single.viewId, 41);

    await oldSub.cancel();
    await newSub.cancel();
    await oldController.dispose();
    await newController.dispose();
  });

  test('handoff rolls back to old controller when new attach fails', () async {
    final oldController = VapController(platform: fakePlatform);
    final failingController = ThrowingAttachVapController(
      platform: fakePlatform,
    );
    oldController.attach(52);

    expect(
      () => handoffVapViewController(
        oldController: oldController,
        newController: failingController,
        viewId: 52,
      ),
      throwsA(isA<StateError>()),
    );

    expect(oldController.viewId, 52);
    expect(failingController.viewId, isNull);
    expect(fakePlatform.disposeCalls, isEmpty);

    await oldController.dispose();
    await failingController.dispose();
  });

  test(
    'swap does not dispose immediately and active controller disposes once',
    () async {
      final oldController = VapController(platform: fakePlatform);
      final newController = VapController(platform: fakePlatform);
      oldController.attach(63);

      handoffVapViewController(
        oldController: oldController,
        newController: newController,
        viewId: 63,
      );
      expect(fakePlatform.disposeCalls, isEmpty);

      await newController.onViewDisposed();
      expect(fakePlatform.disposeCalls, <int>[63]);

      await oldController.onViewDisposed();
      expect(fakePlatform.disposeCalls, <int>[63]);

      await oldController.dispose();
      await newController.dispose();
    },
  );

  test(
    'disposeVapViewControllerSafely reports async disposal errors',
    () async {
      final controller = VapController(platform: fakePlatform);
      controller.attach(91);
      fakePlatform.disposeError = StateError('onViewDisposed failed');
      final FlutterExceptionHandler? previousOnError = FlutterError.onError;
      FlutterErrorDetails? reportedError;
      FlutterError.onError = (FlutterErrorDetails details) {
        reportedError = details;
      };

      try {
        disposeVapViewControllerSafely(controller);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(fakePlatform.disposeCalls, <int>[91]);
        expect(reportedError, isNotNull);
        expect(
          reportedError!.exception.toString(),
          contains('onViewDisposed failed'),
        );
      } finally {
        FlutterError.onError = previousOnError;
      }

      await controller.dispose();
    },
  );
}

class ThrowingAttachVapController extends VapController {
  ThrowingAttachVapController({required VapPlayerPlatform platform})
    : super(platform: platform);

  @override
  void attach(int viewId) {
    throw StateError('attach failed');
  }
}

class FakeVapPlayerPlatform extends VapPlayerPlatform {
  final StreamController<VapPlaybackEvent> _playbackController =
      StreamController<VapPlaybackEvent>.broadcast();
  final StreamController<VapResourceClickEvent> _clickController =
      StreamController<VapResourceClickEvent>.broadcast();
  final Map<int, VapImageResolver> _resolvers = <int, VapImageResolver>{};

  final List<int> disposeCalls = <int>[];
  Object? disposeError;

  @override
  Stream<VapPlaybackEvent> get playbackEvents => _playbackController.stream;

  @override
  Stream<VapResourceClickEvent> get clickEvents => _clickController.stream;

  @override
  void setImageResolver(int viewId, VapImageResolver? resolver) {
    if (resolver == null) {
      _resolvers.remove(viewId);
      return;
    }
    _resolvers[viewId] = resolver;
  }

  bool hasResolverForView(int viewId) => _resolvers.containsKey(viewId);

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
  Future<void> dispose(int viewId) async {
    disposeCalls.add(viewId);
    if (disposeError != null) {
      throw disposeError!;
    }
    _resolvers.remove(viewId);
  }

  @override
  Future<int> getNetworkCacheSizeBytes() async => 0;

  @override
  Future<void> clearNetworkCache() async {}

  @override
  Future<void> pruneNetworkCacheToBytes(int maxBytes) async {}

  @override
  Future<int> getNetworkAutoEvictionMaxBytes() async => 0;

  @override
  Future<void> setNetworkAutoEvictionMaxBytes(int maxBytes) async {}

  void emitPlayback(VapPlaybackEvent event) {
    _playbackController.add(event);
  }
}
