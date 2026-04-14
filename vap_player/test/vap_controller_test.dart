import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vap_player/vap_player.dart';
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

  test('controller play forwards request with attached view id', () async {
    final controller = VapController();
    controller.attach(42);

    await controller.playAsset(
      'assets/demo.mp4',
      repeatCount: 2,
      mute: true,
      contentMode: VapContentMode.aspectFill,
      frameEventsEnabled: true,
      tagValues: const <String, String>{'textUser': 'Alice'},
    );

    final request = fakePlatform.lastPlayRequest;
    expect(request, isNotNull);
    expect(request!.viewId, 42);
    expect(request.sourceType, VapSourceType.asset);
    expect(request.source, 'assets/demo.mp4');
    expect(request.repeatCount, 2);
    expect(request.mute, true);
    expect(request.contentMode, VapContentMode.aspectFill);
    expect(request.frameEventsEnabled, true);
    expect(request.tagValues['textUser'], 'Alice');

    await controller.dispose();
  });

  test('controller filters events by attached view id', () async {
    final controller = VapController();
    controller.attach(7);

    final List<VapPlaybackEvent> events = <VapPlaybackEvent>[];
    final sub = controller.playbackEvents.listen(events.add);

    fakePlatform.emitPlayback(
      const VapPlaybackEvent(viewId: 8, type: VapPlaybackEventType.start),
    );
    fakePlatform.emitPlayback(
      const VapPlaybackEvent(viewId: 7, type: VapPlaybackEventType.start),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(events.length, 1);
    expect(events.single.viewId, 7);

    await sub.cancel();
    await controller.dispose();
  });

  test('setImageResolver registers resolver for current view', () async {
    final controller = VapController();
    controller.attach(11);

    controller.setImageResolver((VapImageResolveRequest request) async {
      return Uint8List.fromList(<int>[1, 2, 3]);
    });

    expect(fakePlatform.hasResolverForView(11), true);

    await controller.dispose();
    expect(fakePlatform.hasResolverForView(11), false);
  });

  test('controller throws when play is called before attach', () async {
    final controller = VapController();
    expect(
      () => controller.playFile('/tmp/demo.mp4'),
      throwsA(isA<StateError>()),
    );
    await controller.dispose();
  });

  test(
    'controller autoPlay queues play before attach and flushes on attach',
    () async {
      final controller = VapController(autoPlay: true);
      final Future<void> playFuture = controller.playAsset('assets/queued.mp4');

      expect(fakePlatform.playRequests, isEmpty);

      controller.attach(101);
      await playFuture;

      expect(fakePlatform.playRequests.length, 1);
      expect(fakePlatform.playRequests.single.viewId, 101);
      expect(fakePlatform.playRequests.single.source, 'assets/queued.mp4');

      await controller.dispose();
    },
  );

  test(
    'controller autoPlay keeps only last pending play before attach',
    () async {
      final controller = VapController(autoPlay: true);

      final Future<void> firstFuture = controller.playFile('/tmp/first.mp4');
      final Future<void> secondFuture = controller.playFile('/tmp/second.mp4');

      await expectLater(firstFuture, throwsA(isA<StateError>()));

      controller.attach(102);
      await secondFuture;

      expect(fakePlatform.playRequests.length, 1);
      expect(fakePlatform.playRequests.single.viewId, 102);
      expect(fakePlatform.playRequests.single.source, '/tmp/second.mp4');

      await controller.dispose();
    },
  );

  test('controller autoPlay cancels pending play on dispose', () async {
    final controller = VapController(autoPlay: true);
    final Future<void> playFuture = controller.playFile('/tmp/pending.mp4');
    final Future<void> expectError = expectLater(
      playFuture,
      throwsA(isA<StateError>()),
    );

    await controller.dispose();

    await expectError;
    expect(fakePlatform.playRequests, isEmpty);
  });

  test(
    'controller allows reattach to same view but rejects different view',
    () async {
      final controller = VapController();
      controller.attach(21);
      controller.attach(21);
      expect(() => controller.attach(22), throwsA(isA<StateError>()));
      await controller.dispose();
    },
  );

  test(
    'controller forwards stop/mute/contentMode/frame-events commands',
    () async {
      final controller = VapController();
      controller.attach(51);

      await controller.stop();
      await controller.setMute(true);
      await controller.setContentMode(VapContentMode.aspectFit);
      await controller.setFrameEventsEnabled(true);

      expect(fakePlatform.lastStopViewId, 51);
      expect(fakePlatform.lastSetMute, (viewId: 51, mute: true));
      expect(fakePlatform.lastSetContentMode, (
        viewId: 51,
        mode: VapContentMode.aspectFit,
      ));
      expect(fakePlatform.lastSetFrameEventsEnabled, (
        viewId: 51,
        enabled: true,
      ));

      await controller.dispose();
    },
  );

  test('controller filters click events by attached view id', () async {
    final controller = VapController();
    controller.attach(9);

    final List<VapResourceClickEvent> events = <VapResourceClickEvent>[];
    final sub = controller.clickEvents.listen(events.add);

    fakePlatform.emitClick(
      const VapResourceClickEvent(viewId: 10, tag: 'other'),
    );
    fakePlatform.emitClick(const VapResourceClickEvent(viewId: 9, tag: 'mine'));

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(events.length, 1);
    expect(events.single.tag, 'mine');

    await sub.cancel();
    await controller.dispose();
  });

  test('onViewDisposed calls platform dispose and detaches view', () async {
    final controller = VapController();
    controller.attach(77);

    await controller.onViewDisposed();

    expect(fakePlatform.disposedViews.contains(77), true);
    expect(controller.viewId, isNull);
    await controller.dispose();
  });
}

class FakeVapPlayerPlatform extends VapPlayerPlatform {
  final StreamController<VapPlaybackEvent> _playbackController =
      StreamController<VapPlaybackEvent>.broadcast();
  final StreamController<VapResourceClickEvent> _clickController =
      StreamController<VapResourceClickEvent>.broadcast();
  final Map<int, VapImageResolver> _resolvers = <int, VapImageResolver>{};

  VapPlayRequest? lastPlayRequest;
  final List<VapPlayRequest> playRequests = <VapPlayRequest>[];
  final Set<int> disposedViews = <int>{};
  int? lastStopViewId;
  ({int viewId, bool mute})? lastSetMute;
  ({int viewId, VapContentMode mode})? lastSetContentMode;
  ({int viewId, bool enabled})? lastSetFrameEventsEnabled;

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
  Future<void> play(VapPlayRequest request) async {
    lastPlayRequest = request;
    playRequests.add(request);
  }

  @override
  Future<void> stop(int viewId) async {
    lastStopViewId = viewId;
  }

  @override
  Future<void> setMute(int viewId, bool mute) async {
    lastSetMute = (viewId: viewId, mute: mute);
  }

  @override
  Future<void> setContentMode(int viewId, VapContentMode mode) async {
    lastSetContentMode = (viewId: viewId, mode: mode);
  }

  @override
  Future<void> setFrameEventsEnabled(int viewId, bool enabled) async {
    lastSetFrameEventsEnabled = (viewId: viewId, enabled: enabled);
  }

  @override
  Future<void> dispose(int viewId) async {
    disposedViews.add(viewId);
    _resolvers.remove(viewId);
  }

  void emitPlayback(VapPlaybackEvent event) {
    _playbackController.add(event);
  }

  void emitClick(VapResourceClickEvent event) {
    _clickController.add(event);
  }
}
