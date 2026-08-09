import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

import 'vap_player_controller.dart';

/// Displays the animation of a [VapPlayerController].
///
/// The widget fills the space given to it, fitting the animation into that
/// space according to [VapPlayerOptions.scaleType]. The renderer itself always
/// fills whatever box this widget gives it; the fit lives here so that it
/// behaves identically across platforms and view types.
///
/// [VapPlayerController.initialize] reads the animation's size from the mp4,
/// so the fit is correct from the first rendered frame.
class VapPlayer extends StatefulWidget {
  /// Creates a player widget for [controller].
  const VapPlayer(this.controller, {super.key});

  /// The controller whose animation is displayed.
  final VapPlayerController controller;

  @override
  State<VapPlayer> createState() => _VapPlayerState();
}

class _VapPlayerState extends State<VapPlayer> {
  late int _playerId;
  late Size _size;

  @override
  void initState() {
    super.initState();
    _playerId = widget.controller.playerId;
    _size = widget.controller.value.size;
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(VapPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      _playerId = widget.controller.playerId;
      _size = widget.controller.value.size;
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    final int newPlayerId = widget.controller.playerId;
    final Size newSize = widget.controller.value.size;
    if (newPlayerId != _playerId || newSize != _size) {
      setState(() {
        _playerId = newPlayerId;
        _size = newSize;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_playerId == kUninitializedPlayerId) {
      return const SizedBox.expand();
    }
    final VapViewOptions options = VapViewOptions(
      playerId: _playerId,
      scaleType: widget.controller.options.scaleType,
      size: _size,
    );
    return _VapFittedView(
      options: options,
      child: VapPlayerPlatform.instance.buildViewWithOptions(options),
    );
  }
}

/// Resizes a renderer to honour [VapViewOptions.scaleType], without ever
/// replacing it: swapping the child when the size arrives would tear down an
/// active platform view and stop playback.
///
/// Only [VapScaleType.centerCrop] can overflow the viewport, so it is the only
/// case that pays for a clip — an expensive layer to put around a platform
/// view. The other cases size the renderer directly instead of scaling it with
/// a transform, which platform views handle poorly.
class _VapFittedView extends StatelessWidget {
  const _VapFittedView({required this.options, required this.child});

  final VapViewOptions options;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Size contentSize = options.size ?? Size.zero;
    // Until the animation's size is known the renderer can only fill.
    if (options.scaleType == VapScaleType.fitXY || contentSize.isEmpty) {
      return child;
    }
    if (options.scaleType == VapScaleType.fitCenter) {
      return _contained(contentSize);
    }

    return ClipRect(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Covering the viewport is undefined without one to measure.
          if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
            return _contained(contentSize);
          }
          final double scale = math.max(
            constraints.maxWidth / contentSize.width,
            constraints.maxHeight / contentSize.height,
          );
          final Size fittedSize = contentSize * scale;
          return OverflowBox(
            alignment: Alignment.center,
            minWidth: fittedSize.width,
            maxWidth: fittedSize.width,
            minHeight: fittedSize.height,
            maxHeight: fittedSize.height,
            child: child,
          );
        },
      ),
    );
  }

  /// The largest centred box with the animation's aspect ratio that fits.
  Widget _contained(Size contentSize) {
    return Center(
      child: AspectRatio(
        aspectRatio: contentSize.width / contentSize.height,
        child: child,
      ),
    );
  }
}
