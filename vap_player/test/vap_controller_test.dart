import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vap_player/flutter_vap_player.dart';
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

  test('play forwards typed asset source and play-scoped options', () async {
    final controller = VapController();
    controller.attach(42);

    await controller.play(
      const VapSource.asset('assets/demo.mp4', package: 'demo_package'),
      options: VapPlaybackOptions(
        loop: true,
        muted: true,
        fit: BoxFit.cover,
        frameEvents: true,
        tags: const <String, String>{'textUser': 'Alice'},
        imageResolver: (_) async => Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );

    final request = fakePlatform.lastPlayRequest;
    expect(request, isNotNull);
    expect(request!.viewId, 42);
    expect(request.sourceType, platform.VapPlatformSourceType.asset);
    expect(request.source, 'assets/demo.mp4');
    expect(request.assetPackage, 'demo_package');
    expect(request.loop, true);
    expect(request.muted, true);
    expect(request.contentMode, platform.VapPlatformContentMode.aspectFill);
    expect(request.frameEvents, true);
    expect(request.tagValues['textUser'], 'Alice');
    expect(fakePlatform.hasResolverForView(42), true);

    await controller.dispose();
  });

  test('play forwards file and network sources', () async {
    final controller = VapController();
    controller.attach(43);

    await controller.play(const VapSource.file('/tmp/demo.mp4'));
    expect(
      fakePlatform.lastPlayRequest!.sourceType,
      platform.VapPlatformSourceType.file,
    );
    expect(fakePlatform.lastPlayRequest!.source, '/tmp/demo.mp4');

    await controller.play(
      VapSource.network(Uri.parse('https://cdn.example.com/vap/demo.mp4')),
    );
    expect(
      fakePlatform.lastPlayRequest!.sourceType,
      platform.VapPlatformSourceType.network,
    );
    expect(
      fakePlatform.lastPlayRequest!.source,
      'https://cdn.example.com/vap/demo.mp4',
    );

    await controller.dispose();
  });

  test('network source rejects non-http absolute URLs', () {
    expect(
      () => VapSource.network(Uri.parse('/local/path.mp4')),
      throwsArgumentError,
    );
    expect(
      () => VapSource.network(Uri.parse('ftp://example.com/demo.mp4')),
      throwsArgumentError,
    );
  });

  test('play rejects BoxFit values without native equivalents', () async {
    final controller = VapController();
    controller.attach(44);

    expect(
      () => controller.play(
        const VapSource.file('/tmp/demo.mp4'),
        options: const VapPlaybackOptions(fit: BoxFit.scaleDown),
      ),
      throwsArgumentError,
    );

    await controller.dispose();
  });

  test('events stream filters by view and maps playback and clicks', () async {
    final controller = VapController();
    controller.attach(7);

    final List<VapEvent> events = <VapEvent>[];
    final sub = controller.events.listen(events.add);

    fakePlatform.emit(
      const platform.VapPlatformPlaybackEvent(
        viewId: 8,
        type: platform.VapPlatformPlaybackEventType.started,
      ),
    );
    fakePlatform.emit(
      const platform.VapPlatformPlaybackEvent(
        viewId: 7,
        type: platform.VapPlatformPlaybackEventType.started,
      ),
    );
    fakePlatform.emit(
      const platform.VapPlatformResourceClickEvent(viewId: 7, tag: 'mine'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(events, hasLength(2));
    expect(events.first, isA<VapPlaybackEvent>());
    expect(
      (events.first as VapPlaybackEvent).type,
      VapPlaybackEventType.started,
    );
    expect(events.last, isA<VapResourceClickEvent>());
    expect((events.last as VapResourceClickEvent).tag, 'mine');

    await sub.cancel();
    await controller.dispose();
  });

  test('play before attach queues latest request by default', () async {
    final controller = VapController();

    final Future<void> firstFuture = controller.play(
      const VapSource.file('/tmp/first.mp4'),
    );
    final Future<void> secondFuture = controller.play(
      const VapSource.file('/tmp/second.mp4'),
    );

    await expectLater(firstFuture, throwsA(isA<StateError>()));

    controller.attach(101);
    await secondFuture;

    expect(fakePlatform.playRequests, hasLength(1));
    expect(fakePlatform.playRequests.single.viewId, 101);
    expect(fakePlatform.playRequests.single.source, '/tmp/second.mp4');

    await controller.dispose();
  });

  test('new play replaces play-scoped image resolver', () async {
    final controller = VapController();
    controller.attach(11);

    await controller.play(
      const VapSource.file('/tmp/first.mp4'),
      options: VapPlaybackOptions(
        imageResolver: (_) async => Uint8List.fromList(<int>[1]),
      ),
    );
    expect(fakePlatform.hasResolverForView(11), true);

    await controller.play(const VapSource.file('/tmp/second.mp4'));
    expect(fakePlatform.hasResolverForView(11), false);

    await controller.dispose();
  });

  test('stop cancels pending play before attachment', () async {
    final controller = VapController();
    final Future<void> playFuture = controller.play(
      const VapSource.file('/tmp/pending.mp4'),
    );

    expect(() => controller.stop(), throwsA(isA<StateError>()));
    await expectLater(playFuture, throwsA(isA<StateError>()));
    await controller.dispose();
  });

  test('view disposal calls platform dispose and detaches', () async {
    final controller = VapController();
    controller.attach(77);

    await controller.onViewDisposed();

    expect(fakePlatform.disposedViews, contains(77));
    await controller.dispose();
  });

  test('view disposal ignores native not-found races', () async {
    final controller = VapController();
    controller.attach(0);
    fakePlatform.disposeError = PlatformException(
      code: 'not-found',
      message: 'No VapView found for viewId=0',
    );

    await controller.onViewDisposed();
    await controller.dispose();
  });
}

class FakeVapPlayerPlatform extends platform.VapPlayerPlatform {
  final StreamController<platform.VapPlatformEvent> _eventsController =
      StreamController<platform.VapPlatformEvent>.broadcast();
  final Map<int, platform.VapPlatformImageResolver> _resolvers =
      <int, platform.VapPlatformImageResolver>{};

  platform.VapPlatformPlayRequest? lastPlayRequest;
  final List<platform.VapPlatformPlayRequest> playRequests =
      <platform.VapPlatformPlayRequest>[];
  final Set<int> disposedViews = <int>{};
  int? lastStopViewId;
  Object? disposeError;
  platform.VapPlatformNetworkCacheInfo cacheInfo =
      const platform.VapPlatformNetworkCacheInfo(sizeBytes: 0, maxBytes: 0);
  int clearNetworkCacheCalls = 0;
  int? lastSetNetworkCacheMaxBytes;

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
  Future<void> play(platform.VapPlatformPlayRequest request) async {
    lastPlayRequest = request;
    playRequests.add(request);
  }

  @override
  Future<void> stop(int viewId) async {
    lastStopViewId = viewId;
  }

  @override
  Future<void> dispose(int viewId) async {
    if (disposeError != null) {
      throw disposeError!;
    }
    disposedViews.add(viewId);
    _resolvers.remove(viewId);
  }

  @override
  Future<platform.VapPlatformNetworkCacheInfo> getNetworkCacheInfo() async {
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

  void emit(platform.VapPlatformEvent event) {
    _eventsController.add(event);
  }
}
