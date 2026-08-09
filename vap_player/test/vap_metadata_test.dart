import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vap_player/src/vap_metadata.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vap_metadata_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String writeFile(List<int> bytes) {
    final File file = File('${tempDir.path}/sample.mp4');
    file.writeAsBytesSync(bytes);
    return file.path;
  }

  test('reads the vapc config of a v2 file', () async {
    final String path = writeFile(<int>[
      ..._ftyp(),
      ..._vapc(
        '{"info":{"v":2,"f":80,"w":736,"h":576,"videoW":752,"videoH":880,'
        '"orien":0,"fps":25,"isVapx":0,"aFrame":[4,588,368,288],'
        '"rgbFrame":[4,4,736,576]}}',
      ),
      ..._moov(<int>[..._videoTrak(752, 880)]),
    ]);

    final VapMetadata? metadata = await readVapMetadata(path);

    expect(metadata, isNotNull);
    expect(metadata!.size, const Size(736, 576));
    expect(metadata.videoSize, const Size(752, 880));
    expect(metadata.frameCount, 80);
    expect(metadata.fps, 25);
    expect(metadata.isMix, false);
    expect(metadata.hasVapcBox, true);
  });

  test('reports isVapx as a mix animation', () async {
    final String path = writeFile(<int>[
      ..._ftyp(),
      ..._vapc(
        '{"info":{"v":2,"f":240,"w":672,"h":1504,"videoW":1104,'
        '"videoH":1504,"fps":20,"isVapx":1}}',
      ),
    ]);

    final VapMetadata? metadata = await readVapMetadata(path);

    expect(metadata!.isMix, true);
    expect(metadata.size, const Size(672, 1504));
  });

  test('halves the video width of a v1 file with no vapc box', () async {
    final String path = writeFile(<int>[
      ..._ftyp(),
      ..._moov(<int>[..._videoTrak(1500, 1000)]),
    ]);

    final VapMetadata? metadata = await readVapMetadata(path);

    expect(metadata, isNotNull);
    // Alpha on the left, colour on the right.
    expect(metadata!.size, const Size(750, 1000));
    expect(metadata.videoSize, const Size(1500, 1000));
    expect(metadata.frameCount, 0);
    expect(metadata.fps, 0);
    expect(metadata.hasVapcBox, false);
  });

  test('skips non-video tracks when deriving a v1 size', () async {
    final String path = writeFile(<int>[
      ..._ftyp(),
      ..._moov(<int>[..._audioTrak(), ..._videoTrak(800, 600)]),
    ]);

    final VapMetadata? metadata = await readVapMetadata(path);

    expect(metadata!.videoSize, const Size(800, 600));
    expect(metadata.size, const Size(400, 600));
  });

  test('skips a box that declares a 64-bit size', () async {
    final String path = writeFile(<int>[
      ..._ftyp(),
      ..._largeBox('mdat', 32),
      ..._moov(<int>[..._videoTrak(1200, 400)]),
    ]);

    final VapMetadata? metadata = await readVapMetadata(path);

    expect(metadata!.videoSize, const Size(1200, 400));
  });

  test('returns null when the vapc config cannot be parsed', () async {
    // A v2 file's frames sit at offsets only the config describes, so the
    // v1 halving must not be used as a fallback.
    final String path = writeFile(<int>[
      ..._ftyp(),
      ..._vapc('{"info":'),
      ..._moov(<int>[..._videoTrak(1500, 1000)]),
    ]);

    expect(await readVapMetadata(path), isNull);
  });

  test('returns null when the vapc config has no usable size', () async {
    final String path = writeFile(<int>[
      ..._ftyp(),
      ..._vapc('{"info":{"v":2,"f":10,"w":0,"h":0}}'),
    ]);

    expect(await readVapMetadata(path), isNull);
  });

  test('returns null for a file with no moov or vapc box', () async {
    expect(await readVapMetadata(writeFile(_ftyp())), isNull);
  });

  test('returns null for a truncated box header', () async {
    expect(await readVapMetadata(writeFile(<int>[0, 0, 1])), isNull);
  });

  test('returns null for a file that is not an mp4', () async {
    expect(
      await readVapMetadata(writeFile(utf8.encode('not an mp4 at all'))),
      isNull,
    );
  });

  test('returns null for a missing file', () async {
    expect(await readVapMetadata('${tempDir.path}/absent.mp4'), isNull);
  });

  test('returns null for a directory', () async {
    expect(await readVapMetadata(tempDir.path), isNull);
  });
}

// ---------------------------------------------------------------------------
// Minimal mp4 box fixtures.
// ---------------------------------------------------------------------------

List<int> _uint32(int value) =>
    <int>[value >> 24 & 0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF];

List<int> _uint16(int value) => <int>[value >> 8 & 0xFF, value & 0xFF];

List<int> _box(String type, List<int> payload) => <int>[
  ..._uint32(payload.length + 8),
  ...ascii.encode(type),
  ...payload,
];

/// A box using the 64-bit `largesize` form, with [payloadSize] filler bytes.
List<int> _largeBox(String type, int payloadSize) => <int>[
  ..._uint32(1),
  ...ascii.encode(type),
  ...Uint8List(4),
  ..._uint32(payloadSize + 16),
  ...Uint8List(payloadSize),
];

List<int> _ftyp() => _box('ftyp', <int>[...ascii.encode('isom'), ..._uint32(512)]);

List<int> _vapc(String json) => _box('vapc', utf8.encode(json));

List<int> _moov(List<int> children) => _box('moov', children);

List<int> _videoTrak(int width, int height) => _box('trak', <int>[
  ..._box('mdia', <int>[
    ..._hdlr('vide'),
    ..._box('minf', <int>[
      ..._box('stbl', <int>[..._stsd(width, height)]),
    ]),
  ]),
]);

List<int> _audioTrak() => _box('trak', <int>[
  ..._box('mdia', <int>[
    ..._hdlr('soun'),
    ..._box('minf', <int>[
      ..._box('stbl', <int>[
        ..._box('stsd', <int>[
          ..._uint32(0),
          ..._uint32(1),
          ..._box('mp4a', Uint8List(28)),
        ]),
      ]),
    ]),
  ]),
]);

/// version and flags, pre_defined, handler_type, reserved, name.
List<int> _hdlr(String handler) => _box('hdlr', <int>[
  ..._uint32(0),
  ..._uint32(0),
  ...ascii.encode(handler),
  ...Uint8List(12),
  0,
]);

/// version and flags, entry_count, then one visual sample entry.
List<int> _stsd(int width, int height) => _box('stsd', <int>[
  ..._uint32(0),
  ..._uint32(1),
  ..._avc1(width, height),
]);

/// reserved, data_reference_index, pre_defined, reserved, pre_defined[3],
/// width, height, then the remainder of the visual sample entry.
List<int> _avc1(int width, int height) => _box('avc1', <int>[
  ...Uint8List(6),
  ..._uint16(1),
  ...Uint8List(16),
  ..._uint16(width),
  ..._uint16(height),
  ...Uint8List(50),
]);
