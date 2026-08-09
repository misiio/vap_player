import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show immutable;

/// Animation metadata read from a VAP mp4 before playback starts.
///
/// The native players only report this once they have parsed the file, which
/// for VAP v1 files is not until the first frame has been rendered. Reading it
/// up front lets the animation be laid out correctly from its very first
/// frame.
@immutable
class VapMetadata {
  /// Creates metadata for a VAP mp4.
  const VapMetadata({
    required this.size,
    required this.videoSize,
    required this.frameCount,
    required this.fps,
    required this.isMix,
    required this.hasVapcBox,
  });

  /// Intended display size of the animation.
  final Size size;

  /// Size of the underlying mp4 video, which packs the alpha and colour
  /// frames side by side.
  final Size videoSize;

  /// Total number of frames, or 0 when the file does not declare it.
  final int frameCount;

  /// Frames per second, or 0 when the file does not declare it.
  final int fps;

  /// Whether the animation declares VAPX mix resources.
  final bool isMix;

  /// Whether the file carries a `vapc` box (a VAP v2 file).
  final bool hasVapcBox;
}

/// The size of a plain mp4 box header (32-bit size plus a four-character
/// type). Boxes that need a 64-bit size carry it in the following 8 bytes.
const int _boxHeaderSize = 8;

/// The `vapc` payload is a small JSON blob; anything larger is not one.
const int _maxVapcBoxSize = 4 * 1024 * 1024;

/// `moov` is read into memory to walk its children, so cap it.
const int _maxMoovBoxSize = 16 * 1024 * 1024;

/// Reads the animation metadata from the VAP mp4 at [path].
///
/// Returns null when the file cannot be read or does not describe a VAP
/// animation; callers then fall back to the platform's config-ready event.
/// This never throws.
Future<VapMetadata?> readVapMetadata(String path) async {
  final RandomAccessFile file;
  try {
    file = await File(path).open();
  } catch (_) {
    return null;
  }
  try {
    return await _readMetadata(file);
  } catch (_) {
    return null;
  } finally {
    try {
      await file.close();
    } catch (_) {
      // Nothing useful to do when the handle cannot be closed.
    }
  }
}

Future<VapMetadata?> _readMetadata(RandomAccessFile file) async {
  final int fileLength = await file.length();
  Uint8List? vapcPayload;
  Uint8List? moovPayload;

  int offset = 0;
  while (offset + _boxHeaderSize <= fileLength &&
      (vapcPayload == null || moovPayload == null)) {
    await file.setPosition(offset);
    final Uint8List header = await file.read(16);
    if (header.length < _boxHeaderSize) {
      break;
    }
    final ByteData headerData = ByteData.sublistView(header);

    int headerSize = _boxHeaderSize;
    int boxSize = headerData.getUint32(0);
    if (boxSize == 1) {
      if (header.length < 16) {
        break;
      }
      boxSize = headerData.getUint64(8);
      headerSize = 16;
    } else if (boxSize == 0) {
      // A zero size means the box extends to the end of the file.
      boxSize = fileLength - offset;
    }
    if (boxSize < headerSize) {
      break;
    }
    // Tolerate a final box whose declared size overruns the file.
    boxSize = math.min(boxSize, fileLength - offset);

    final String type = _boxType(header, 4);
    final int payloadSize = boxSize - headerSize;
    if (type == 'vapc' && payloadSize > 0 && payloadSize <= _maxVapcBoxSize) {
      await file.setPosition(offset + headerSize);
      vapcPayload = await file.read(payloadSize);
    } else if (type == 'moov' &&
        payloadSize > 0 &&
        payloadSize <= _maxMoovBoxSize) {
      await file.setPosition(offset + headerSize);
      moovPayload = await file.read(payloadSize);
    }
    offset += boxSize;
  }

  if (vapcPayload != null) {
    // A v2 file packs its frames at arbitrary offsets described by the vapc
    // config, so there is nothing to derive if that config cannot be read.
    return _metadataFromVapc(vapcPayload);
  }
  if (moovPayload == null) {
    return null;
  }
  final Size? videoSize = _videoTrackSize(moovPayload);
  if (videoSize == null || videoSize.width < 2 || videoSize.height <= 0) {
    return null;
  }
  // VAP v1 files carry no config. Their frames are split horizontally into
  // two equal halves — alpha on the left, colour on the right — which is what
  // VAP's default video mode assumes on both platforms.
  return VapMetadata(
    size: Size((videoSize.width / 2).floorToDouble(), videoSize.height),
    videoSize: videoSize,
    frameCount: 0,
    fps: 0,
    isMix: false,
    hasVapcBox: false,
  );
}

VapMetadata? _metadataFromVapc(Uint8List payload) {
  final Object? decoded;
  try {
    // The box can carry padding after the JSON object, so stop at the closing
    // brace rather than feeding the whole payload to the parser.
    final String text = utf8.decode(payload, allowMalformed: true);
    final int end = text.lastIndexOf('}');
    if (end < 0) {
      return null;
    }
    decoded = jsonDecode(text.substring(0, end + 1));
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final Object? info = decoded['info'];
  if (info is! Map<String, Object?>) {
    return null;
  }
  final int? width = _asInt(info['w']);
  final int? height = _asInt(info['h']);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return VapMetadata(
    size: Size(width.toDouble(), height.toDouble()),
    videoSize: Size(
      (_asInt(info['videoW']) ?? width).toDouble(),
      (_asInt(info['videoH']) ?? height).toDouble(),
    ),
    frameCount: _asInt(info['f']) ?? 0,
    fps: _asInt(info['fps']) ?? 0,
    isMix: _asInt(info['isVapx']) == 1,
    hasVapcBox: true,
  );
}

/// Returns the coded size of the first video track described by [moov].
Size? _videoTrackSize(Uint8List moov) {
  for (final _Box trak in _childBoxes(moov, 0, moov.length)) {
    if (trak.type != 'trak') {
      continue;
    }
    final Size? size = _videoSizeInTrak(moov, trak);
    if (size != null) {
      return size;
    }
  }
  return null;
}

Size? _videoSizeInTrak(Uint8List data, _Box trak) {
  final _Box? mdia = _firstChild(data, trak, 'mdia');
  if (mdia == null) {
    return null;
  }
  // hdlr payload: version and flags (4), pre_defined (4), handler_type (4).
  final _Box? hdlr = _firstChild(data, mdia, 'hdlr');
  if (hdlr == null ||
      hdlr.start + 12 > hdlr.end ||
      _boxType(data, hdlr.start + 8) != 'vide') {
    return null;
  }
  final _Box? minf = _firstChild(data, mdia, 'minf');
  final _Box? stbl = minf == null ? null : _firstChild(data, minf, 'stbl');
  final _Box? stsd = stbl == null ? null : _firstChild(data, stbl, 'stsd');
  if (stsd == null || stsd.start + 8 > stsd.end) {
    return null;
  }

  // stsd payload: version and flags (4), entry_count (4), sample entries.
  final ByteData view = ByteData.sublistView(data);
  for (final _Box entry in _childBoxes(data, stsd.start + 8, stsd.end)) {
    // VisualSampleEntry payload: reserved (6), data_reference_index (2),
    // pre_defined (2), reserved (2), pre_defined[3] (12), width, height.
    if (entry.start + 28 > entry.end) {
      continue;
    }
    final int width = view.getUint16(entry.start + 24);
    final int height = view.getUint16(entry.start + 26);
    if (width > 0 && height > 0) {
      return Size(width.toDouble(), height.toDouble());
    }
  }
  return null;
}

/// A child box's four-character type and the bounds of its payload.
class _Box {
  const _Box(this.type, this.start, this.end);

  final String type;
  final int start;
  final int end;
}

Iterable<_Box> _childBoxes(Uint8List data, int start, int end) sync* {
  final ByteData view = ByteData.sublistView(data);
  int offset = start;
  while (offset + _boxHeaderSize <= end) {
    int headerSize = _boxHeaderSize;
    int boxSize = view.getUint32(offset);
    if (boxSize == 1) {
      if (offset + 16 > end) {
        return;
      }
      boxSize = view.getUint64(offset + 8);
      headerSize = 16;
    } else if (boxSize == 0) {
      boxSize = end - offset;
    }
    if (boxSize < headerSize) {
      return;
    }
    yield _Box(
      _boxType(data, offset + 4),
      offset + headerSize,
      math.min(offset + boxSize, end),
    );
    offset += boxSize;
  }
}

_Box? _firstChild(Uint8List data, _Box parent, String type) {
  for (final _Box child in _childBoxes(data, parent.start, parent.end)) {
    if (child.type == type) {
      return child;
    }
  }
  return null;
}

String _boxType(Uint8List data, int offset) {
  if (offset + 4 > data.length) {
    return '';
  }
  return String.fromCharCodes(data, offset, offset + 4);
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
