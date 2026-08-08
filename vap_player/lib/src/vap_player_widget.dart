import 'package:flutter/widgets.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

import 'vap_player_controller.dart';

/// Displays the animation of a [VapPlayerController].
///
/// The widget fills the space given to it, fitting the animation into
/// that space according to [VapPlayerOptions.scaleType] (in texture mode
/// the fit is applied once the animation's config is parsed and its size
/// is known).
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
    return VapPlayerPlatform.instance.buildViewWithOptions(
      VapViewOptions(
        playerId: _playerId,
        scaleType: widget.controller.options.scaleType,
        size: _size,
      ),
    );
  }
}
