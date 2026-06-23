import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vap_player/src/vap_controller.dart';
import 'package:flutter_vap_player/src/vap_models.dart';
import 'package:flutter_vap_player/src/vap_view.dart';
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

  test('handoff detaches old controller and attaches new controller', () async {
    final oldController = VapController();
    final newController = VapController();
    final List<VapEvent> oldEvents = <VapEvent>[];
    final List<VapEvent> newEvents = <VapEvent>[];
    final oldSub = oldController.events.listen(oldEvents.add);
    final newSub = newController.events.listen(newEvents.add);

    oldController.attach(41);
    await oldController.play(
      const VapSource.file('/tmp/old.mp4'),
      options: VapPlaybackOptions(imageResolver: (_) async => null),
    );
    expect(fakePlatform.hasResolverForView(41), true);

    handoffVapViewController(
      oldController: oldController,
      newController: newController,
      viewId: 41,
    );

    expect(fakePlatform.hasResolverForView(41), false);
    expect(fakePlatform.disposeCalls, isEmpty);

    fakePlatform.emit(
      const platform.VapPlatformPlaybackEvent(
        viewId: 41,
        type: platform.VapPlatformPlaybackEventType.started,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(oldEvents, isEmpty);
    expect(newEvents, hasLength(1));

    await oldSub.cancel();
    await newSub.cancel();
    await oldController.dispose();
    await newController.dispose();
  });

  test('handoff rolls back to old controller when new attach fails', () async {
    final oldController = VapController();
    final failingController = ThrowingAttachVapController();
    final List<VapEvent> oldEvents = <VapEvent>[];
    final oldSub = oldController.events.listen(oldEvents.add);
    oldController.attach(52);

    expect(
      () => handoffVapViewController(
        oldController: oldController,
        newController: failingController,
        viewId: 52,
      ),
      throwsA(isA<StateError>()),
    );

    fakePlatform.emit(
      const platform.VapPlatformPlaybackEvent(
        viewId: 52,
        type: platform.VapPlatformPlaybackEventType.started,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(oldEvents, hasLength(1));
    expect(fakePlatform.disposeCalls, isEmpty);

    await oldSub.cancel();
    await oldController.dispose();
    await failingController.dispose();
  });

  test(
    'swap does not dispose immediately and active controller disposes once',
    () async {
      final oldController = VapController();
      final newController = VapController();
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
      final controller = VapController();
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
  @override
  void attach(int viewId) {
    throw StateError('attach failed');
  }
}

class FakeVapPlayerPlatform extends platform.VapPlayerPlatform {
  final StreamController<platform.VapPlatformEvent> _eventsController =
      StreamController<platform.VapPlatformEvent>.broadcast();
  final Map<int, platform.VapPlatformImageResolver> _resolvers =
      <int, platform.VapPlatformImageResolver>{};

  final List<int> disposeCalls = <int>[];
  Object? disposeError;

  @override
  Stream<platform.VapPlatformEvent> get events => _eventsController.stream;

  @override
  void setImageResolver(
    int viewId,
    platform.VapPlatformImageResolver? resolver,
  ) {
    if (resolver == null) {
      _resolvers.remove(viewId);
      return;
    }
    _resolvers[viewId] = resolver;
  }

  bool hasResolverForView(int viewId) => _resolvers.containsKey(viewId);

  @override
  Future<void> play(platform.VapPlatformPlayRequest request) async {}

  @override
  Future<void> stop(int viewId) async {}

  @override
  Future<void> dispose(int viewId) async {
    disposeCalls.add(viewId);
    if (disposeError != null) {
      throw disposeError!;
    }
    _resolvers.remove(viewId);
  }

  @override
  Future<platform.VapPlatformNetworkCacheInfo> getNetworkCacheInfo() async {
    return const platform.VapPlatformNetworkCacheInfo(
      sizeBytes: 0,
      maxBytes: 0,
    );
  }

  @override
  Future<void> clearNetworkCache() async {}

  @override
  Future<void> setNetworkCacheMaxBytes(int maxBytes) async {}

  void emit(platform.VapPlatformEvent event) {
    _eventsController.add(event);
  }
}
