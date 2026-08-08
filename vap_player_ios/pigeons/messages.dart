import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    swiftOut: 'ios/vap_player_ios/Sources/vap_player_ios/messages.g.swift',
    dartPackageName: 'vap_player_ios',
  ),
)
/// Pigeon equivalent of the iOS QGVAPWrapViewContentMode.
enum PlatformContentMode { scaleToFill, aspectFit, aspectFill }

/// Pigeon equivalent of VapResourceType.
enum PlatformResourceType { image, text }

class PlatformCreationOptions {
  PlatformCreationOptions({required this.enableFrameEvents});
  bool enableFrameEvents;
}

class PlatformPlayOptions {
  PlatformPlayOptions({
    required this.path,
    required this.repeatCount,
    required this.mute,
    required this.contentMode,
    required this.enableOldVersion,
  });
  String path;

  /// 0 = play once, n = play n+1 times, -1 = loop forever.
  int repeatCount;
  bool mute;
  PlatformContentMode contentMode;

  /// Enables playback of plain alpha mp4s without a `vapc` box.
  bool enableOldVersion;
}

/// A VAPX mix resource placeholder.
class PlatformVapResource {
  PlatformVapResource({
    required this.id,
    required this.type,
    required this.tag,
  });
  String id;
  PlatformResourceType type;
  String tag;
}

sealed class PlatformVapEvent {}

/// Sent when the vapc config is parsed, right before rendering starts.
class ConfigReadyEvent extends PlatformVapEvent {
  late final int width;
  late final int height;
  late final int videoWidth;
  late final int videoHeight;
  late final int frameCount;
  late final int fps;
  late final bool isMix;
}

/// Sent when the first frame is rendered.
class StartedEvent extends PlatformVapEvent {}

/// Sent per rendered frame, only when enableFrameEvents was requested.
class FrameRenderedEvent extends PlatformVapEvent {
  late final int frameIndex;
}

/// Sent when playback finishes (all repeats done, or stopped).
class CompletedEvent extends PlatformVapEvent {}

/// Sent when the native player has released its resources.
class DestroyedEvent extends PlatformVapEvent {}

/// Sent when playback fails.
class FailedEvent extends PlatformVapEvent {
  late final int errorType;
  late final String? errorMsg;
}

/// Sent when a VAPX resource is tapped.
class ResourceClickedEvent extends PlatformVapEvent {
  late final PlatformVapResource resource;
}

@HostApi()
abstract class IosVapPlayerApi {
  void initialize();

  /// Creates a player; returns the player id.
  int create(PlatformCreationOptions options);

  void dispose(int playerId);
}

@HostApi()
abstract class VapPlayerInstanceApi {
  /// Starts playback from the first frame.
  void play(PlatformPlayOptions options);

  /// Stops playback.
  void stop();

  /// Pauses playback.
  void pause();

  /// Resumes playback after pause.
  void resume();

  /// Mutes/unmutes; only takes effect at the next play/loop start.
  void setMute(bool mute);

  /// Sets the repeat count for subsequent plays.
  void setRepeatCount(int repeatCount);

  /// Tells native whether a Dart resource delegate exists.
  void setHasResourceDelegate(bool hasDelegate);
}

@FlutterApi()
abstract class VapResourceFlutterApi {
  @async
  String? resolveText(int playerId, PlatformVapResource resource);

  @async
  Uint8List? resolveImage(int playerId, PlatformVapResource resource);
}

@EventChannelApi()
abstract class VapEventChannelApi {
  PlatformVapEvent vapEvents();
}
