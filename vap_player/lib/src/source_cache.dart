import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Materializes VAP data sources into local files, since the native VAP
/// libraries only play local file paths.
class SourceCache {
  SourceCache._();

  static Directory get _cacheDir =>
      Directory('${Directory.systemTemp.path}/vap_player_cache');

  static String _keyFor(String identity) =>
      sha1.convert(utf8.encode(identity)).toString();

  /// Copies a Flutter asset to a cache file once and returns its path.
  static Future<String> materializeAsset(String assetKey) async {
    final File file = File('${_cacheDir.path}/asset_${_keyFor(assetKey)}.mp4');
    if (!file.existsSync() || file.lengthSync() == 0) {
      final ByteData data = await rootBundle.load(assetKey);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  /// Downloads a network URL to a cache file once and returns its path.
  static Future<String> materializeNetwork(
    Uri url, {
    Map<String, String>? httpHeaders,
  }) async {
    final File file = File(
      '${_cacheDir.path}/net_${_keyFor(url.toString())}.mp4',
    );
    if (file.existsSync() && file.lengthSync() > 0) {
      return file.path;
    }
    await file.parent.create(recursive: true);
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(url);
      httpHeaders?.forEach(request.headers.set);
      final HttpClientResponse response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to download VAP file: HTTP ${response.statusCode}',
          uri: url,
        );
      }
      final File tempFile = File('${file.path}.part');
      final IOSink sink = tempFile.openWrite();
      await response.pipe(sink);
      await tempFile.rename(file.path);
    } finally {
      client.close();
    }
    return file.path;
  }
}
