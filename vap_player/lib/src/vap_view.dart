import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'vap_controller.dart';

class VapView extends StatefulWidget {
  const VapView({
    super.key,
    required this.controller,
    this.hitTestBehavior = PlatformViewHitTestBehavior.opaque,
  });

  static const String viewType = 'vap_player/view';

  final VapController controller;
  final PlatformViewHitTestBehavior hitTestBehavior;

  @override
  State<VapView> createState() => _VapViewState();
}

class _VapViewState extends State<VapView> {
  bool _viewCreated = false;

  @override
  void dispose() {
    if (_viewCreated) {
      unawaited(widget.controller.onViewDisposed());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: VapView.viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        hitTestBehavior: widget.hitTestBehavior,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: VapView.viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        hitTestBehavior: widget.hitTestBehavior,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    throw UnsupportedError('VapView is only supported on Android and iOS.');
  }

  void _onPlatformViewCreated(int viewId) {
    _viewCreated = true;
    widget.controller.attach(viewId);
  }
}
