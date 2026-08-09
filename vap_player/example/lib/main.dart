import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vap_player/flutter_vap_player.dart';

void main() {
  runApp(const VapExampleApp());
}

class VapExampleApp extends StatelessWidget {
  const VapExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vap_player example',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('vap_player example')),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: const Text('Texture mode'),
            subtitle: Text(
              Platform.isIOS
                  ? 'Falls back to PlatformView on iOS'
                  : 'Renders into a Flutter Texture',
            ),
            onTap: () => _open(context, const PlayerPage.texture()),
          ),
          ListTile(
            title: const Text('PlatformView mode'),
            subtitle: const Text('Native view with scale-type switching'),
            onTap: () => _open(context, const PlayerPage.platformView()),
          ),
          ListTile(
            title: const Text('VAPX (mix resources)'),
            subtitle: const Text('Dynamic text and image injection'),
            onTap: () => _open(context, const VapxPage()),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => page));
  }
}

/// The demo animations. `test.mp4` has no `vapc` box (a VAP v1 file), so it
/// exercises the path where the animation's size can only come from the mp4
/// header; the others carry a config.
enum DemoSource {
  v1('test.mp4', 'V1'),
  v2('test2.mp4', 'V2'),
  demo('demo.mp4', 'Demo');

  const DemoSource(this.fileName, this.label);

  final String fileName;
  final String label;

  String get assetKey => 'assets/vap/$fileName';
}

class PlayerPage extends StatefulWidget {
  const PlayerPage.texture({super.key}) : viewType = VapViewType.textureView;
  const PlayerPage.platformView({super.key})
    : viewType = VapViewType.platformView;

  final VapViewType viewType;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VapPlayerController? _controller;
  VapScaleType _scaleType = VapScaleType.fitCenter;
  DemoSource _source = DemoSource.v1;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  Future<void> _createController() async {
    final VapPlayerController controller = VapPlayerController.asset(
      _source.assetKey,
      options: VapPlayerOptions(
        viewType: widget.viewType,
        repeatCount: -1,
        scaleType: _scaleType,
        enableOldVersion: true,
      ),
    );
    setState(() {
      _controller = controller;
    });
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {});
    await controller.play();
  }

  /// Options are fixed for a controller's lifetime, so changing one means
  /// tearing the player down and building a new one.
  Future<void> _restart() async {
    final VapPlayerController? old = _controller;
    _controller = null;
    setState(() {});
    await old?.dispose();
    await _createController();
  }

  Future<void> _switchScaleType(VapScaleType scaleType) async {
    _scaleType = scaleType;
    await _restart();
  }

  Future<void> _switchSource(DemoSource source) async {
    _source = source;
    await _restart();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VapPlayerController? controller = _controller;
    final bool isPlatformView = widget.viewType == VapViewType.platformView;
    return Scaffold(
      appBar: AppBar(
        title: Text(isPlatformView ? 'PlatformView mode' : 'Texture mode'),
      ),
      // A gradient background proves the animation's alpha channel works.
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF16222A), Color(0xFF3A6073)],
          ),
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: controller == null || !controller.value.isInitialized
                  ? const Center(child: CircularProgressIndicator())
                  : VapPlayer(controller),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // The size is read from the mp4 during initialize(), so it
                    // is already correct before the first frame renders.
                    if (controller != null)
                      ValueListenableBuilder<VapPlayerValue>(
                        valueListenable: controller,
                        builder: (BuildContext context, VapPlayerValue value, _) {
                          final Size size = value.size;
                          final Size video = value.videoSize;
                          return Text(
                            'size ${size.width.toInt()}×${size.height.toInt()}'
                            '   video ${video.width.toInt()}'
                            '×${video.height.toInt()}'
                            '   ${value.frameCount} frames @ ${value.fps}fps',
                            style: const TextStyle(color: Colors.white70),
                          );
                        },
                      ),
                    const SizedBox(height: 8),
                    SegmentedButton<DemoSource>(
                      segments: <ButtonSegment<DemoSource>>[
                        for (final DemoSource source in DemoSource.values)
                          ButtonSegment<DemoSource>(
                            value: source,
                            label: Text(source.label),
                          ),
                      ],
                      selected: <DemoSource>{_source},
                      onSelectionChanged: (Set<DemoSource> selection) {
                        _switchSource(selection.first);
                      },
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<VapScaleType>(
                      segments: const <ButtonSegment<VapScaleType>>[
                        ButtonSegment<VapScaleType>(
                          value: VapScaleType.fitXY,
                          label: Text('fitXY'),
                        ),
                        ButtonSegment<VapScaleType>(
                          value: VapScaleType.fitCenter,
                          label: Text('fitCenter'),
                        ),
                        ButtonSegment<VapScaleType>(
                          value: VapScaleType.centerCrop,
                          label: Text('centerCrop'),
                        ),
                      ],
                      selected: <VapScaleType>{_scaleType},
                      onSelectionChanged: (Set<VapScaleType> selection) {
                        _switchScaleType(selection.first);
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton(
                          onPressed: () => controller?.play(),
                          child: const Text('Play'),
                        ),
                        FilledButton(
                          onPressed: () => controller?.stop(),
                          child: const Text('Stop'),
                        ),
                        FilledButton(
                          onPressed: (controller?.value.canPause ?? false)
                              ? () => controller?.pause()
                              : null,
                          child: const Text('Pause'),
                        ),
                        FilledButton(
                          onPressed: (controller?.value.canPause ?? false)
                              ? () => controller?.resume()
                              : null,
                          child: const Text('Resume'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VapxPage extends StatefulWidget {
  const VapxPage({super.key});

  @override
  State<VapxPage> createState() => _VapxPageState();
}

class _VapxPageState extends State<VapxPage> {
  VapPlayerController? _controller;
  bool _useFirstHead = true;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  Future<void> _createController() async {
    final VapPlayerController controller = VapPlayerController.asset(
      'assets/vap/vapx.mp4',
      options: VapPlayerOptions(
        repeatCount: -1,
        scaleType: VapScaleType.fitXY,
        resourceDelegate: VapResourceDelegate(
          resolveText: (VapResource resource) async {
            // Any non-empty tag in this demo animation gets text content.
            return 'Congrats to No.${1000 + Random().nextInt(8999)} for winning the Grand Prize!';
          },
          resolveImage: (VapResource resource) async {
            final String asset = _useFirstHead
                ? 'assets/img/head1.png'
                : 'assets/img/head2.png';
            _useFirstHead = !_useFirstHead;
            final ByteData data = await rootBundle.load(asset);
            return data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
          },
        ),
        onResourceClick: (VapResource resource) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tapped resource: ${resource.tag}')),
          );
        },
      ),
    );
    setState(() {
      _controller = controller;
    });
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {});
    await controller.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VapPlayerController? controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('VAPX (mix resources)')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF2C003E), Color(0xFF8E2DE2)],
          ),
        ),
        child: controller == null || !controller.value.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : VapPlayer(controller),
      ),
    );
  }
}
