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
  const VapResource({required this.id, required this.type, required this.tag});

  /// The source id from the animation's vapc config.
  final String id;

  /// Whether this slot expects an image or text.
  final VapResourceType type;

  /// The business tag identifying the slot (e.g. `[sImg1]`, `[textUser]`).
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is VapResource &&
      other.id == id &&
      other.type == type &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(id, type, tag);

  @override
  String toString() => 'VapResource(id: $id, type: $type, tag: $tag)';
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
