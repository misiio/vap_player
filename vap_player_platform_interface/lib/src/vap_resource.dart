import 'package:flutter/foundation.dart';

/// The kind of resource a VAPX animation is requesting.
enum VapResourceType {
  /// An image slot; provide encoded image bytes.
  image,

  /// A text slot; provide a string.
  text,
}

/// A VAPX (mix/fusion) resource placeholder embedded in the animation.
@immutable
class VapResource {
  /// Creates a resource description.
  const VapResource({
    required this.id,
    required this.type,
    required this.tag,
    this.width,
    this.height,
  });

  /// The source id from the animation's vapc config.
  final String id;

  /// Whether this slot expects an image or text.
  final VapResourceType type;

  /// The business tag identifying the slot (e.g. `[sImg1]`, `[textUser]`).
  final String tag;

  /// The slot's width in the animation's own pixels (its vapc `w`), or null
  /// when unknown.
  ///
  /// The native player stretches whatever fills the slot to this size, so an
  /// image drawn at exactly [width] × [height] is shown undistorted.
  final int? width;

  /// The slot's height in the animation's own pixels (its vapc `h`), or null
  /// when unknown.
  final int? height;

  /// Returns a copy with the given slot size.
  VapResource withSize({required int width, required int height}) =>
      VapResource(id: id, type: type, tag: tag, width: width, height: height);

  @override
  bool operator ==(Object other) =>
      other is VapResource &&
      other.id == id &&
      other.type == type &&
      other.tag == tag &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(id, type, tag, width, height);

  @override
  String toString() =>
      'VapResource(id: $id, type: $type, tag: $tag, width: $width, height: $height)';
}

/// Supplies VAPX resources for a player.
///
/// Must be registered before playback starts. When the animation declares
/// mix resources, the platform implementation calls these callbacks and
/// blocks the (native) render pipeline until they complete, so keep them
/// fast; native code applies a timeout after which the slot stays empty.
@immutable
class VapResourceDelegate {
  /// Creates a delegate.
  const VapResourceDelegate({this.resolveText, this.resolveImage});

  /// Returns the text to render for a [VapResourceType.text] resource,
  /// or null to leave the slot empty.
  final Future<String?> Function(VapResource resource)? resolveText;

  /// Returns encoded image bytes (PNG/JPEG) for a [VapResourceType.image]
  /// resource, or null to leave the slot empty. Bytes are decoded natively.
  final Future<Uint8List?> Function(VapResource resource)? resolveImage;
}
