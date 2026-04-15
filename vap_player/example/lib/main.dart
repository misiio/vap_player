import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vap_player/flutter_vap_player.dart';

void main() {
  runApp(const MaterialApp(home: VapDemoPage()));
}

class VapDemoPage extends StatefulWidget {
  const VapDemoPage({super.key});

  @override
  State<VapDemoPage> createState() => _VapDemoPageState();
}

class _VapDemoPageState extends State<VapDemoPage> {
  final VapController _controller = VapController();
  final List<String> _logs = <String>[];

  @override
  void initState() {
    super.initState();
    _controller.setImageResolver(_resolveImage);
    _controller.playbackEvents.listen((VapPlaybackEvent event) {
      _addLog(
        'playback: ${event.type} frame=${event.frameIndex} error=${event.errorMessage}',
      );
    });
    _controller.clickEvents.listen((VapResourceClickEvent event) {
      _addLog(
        'click: tag=${event.tag} rect=(${event.x}, ${event.y}, ${event.width}, ${event.height})',
      );
    });
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VAP Player Demo')),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueGrey),
                ),
                child: VapView(controller: _controller),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: <Widget>[
              ElevatedButton(
                onPressed: _playClassic,
                child: const Text('Play Demo Asset'),
              ),
              ElevatedButton(
                onPressed: _playVapx,
                child: const Text('Play VAPX Asset'),
              ),
              ElevatedButton(onPressed: _stop, child: const Text('Stop')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (BuildContext context, int index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: Text(_logs[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playClassic() async {
    await _controller.playAsset(
      'assets/demo.mp4',
      repeatCount: 0,
      mute: false,
      contentMode: VapContentMode.aspectFit,
    );
  }

  Future<void> _playVapx() async {
    await _controller.playAsset(
      'assets/vap.mp4',
      repeatCount: -1,
      mute: true,
      contentMode: VapContentMode.aspectFit,
      tagValues: const <String, String>{
        '[sImg1]': 'demo://qq_avatar',
        '[textAnchor]': 'Streamer Alice',
        '[textUser]': 'User Bob',
      },
    );
  }

  Future<void> _stop() async {
    await _controller.stop();
  }

  Future<Uint8List?> _resolveImage(VapImageResolveRequest request) async {
    if (request.url == 'demo://qq_avatar' || request.tag == '[sImg1]') {
      final ByteData data = await rootBundle.load('assets/qq.png');
      return data.buffer.asUint8List();
    }
    return null;
  }

  void _addLog(String text) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.insert(0, '${DateTime.now().toIso8601String()} $text');
      if (_logs.length > 100) {
        _logs.removeRange(100, _logs.length);
      }
    });
  }
}
