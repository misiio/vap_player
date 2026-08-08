import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/app/misi/vap_player_android/Messages.kt',
    kotlinOptions: KotlinOptions(package: 'app.misi.vap_player_android'),
    dartPackageName: 'vap_player_android',
  ),
)
/// Pigeon equivalent of VapViewType.
enum PlatformVapViewType { textureView, platformView }

/// Pigeon equivalent of VapScaleType.
enum PlatformScaleType { fitXY, fitCenter, centerCrop }

/// Pigeon equivalent of VapResourceType.
enum PlatformResourceType { image, text }

/// Information passed to the platform view creation.
class PlatformVapViewCreationParams {
  const PlatformVapViewCreationParams({required this.playerId});

  final int playerId;
}

class PlatformCreationOptions {
  PlatformCreationOptions({
    required this.viewType,
    required this.enableFrameEvents,
  });
  PlatformVapViewType viewType;
  bool enableFrameEvents;
}

class TexturePlayerIds {
  TexturePlayerIds({required this.playerId, required this.textureId});

  final int playerId;
  final int textureId;
}

class PlatformPlayOptions {
  PlatformPlayOptions({
    required this.path,
    required this.repeatCount,
    required this.mute,
    required this.scaleType,
    required this.enableOldVersion,
    this.fps,
  });
  String path;

  /// 0 = play once, n = play n+1 times, -1 = loop forever.
  int repeatCount;
  bool mute;
  PlatformScaleType scaleType;

  /// Enables VAP v1 playback for mp4s that lack a `vapc` box.
  bool enableOldVersion;
  int? fps;
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
abstract class AndroidVapPlayerApi {
  void initialize();

  /// Creates a player rendering into a platform view; returns the player id.
  int createForPlatformView(PlatformCreationOptions options);

  /// Creates a player rendering into a Flutter texture; returns its ids.
  TexturePlayerIds createForTextureView(PlatformCreationOptions options);

  void dispose(int playerId);
}

@HostApi()
abstract class VapPlayerInstanceApi {
  /// Starts playback from the first frame.
  void play(PlatformPlayOptions options);

  /// Stops playback.
  void stop();

  /// Mutes/unmutes the audio track for subsequent plays.
  void setMute(bool mute);

  /// Sets the repeat count for subsequent plays (same semantics as
  /// PlatformPlayOptions.repeatCount).
  void setRepeatCount(int repeatCount);

  /// Tells native whether a Dart resource delegate exists; when false,
  /// VAPX fetch callbacks resolve to null immediately.
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
