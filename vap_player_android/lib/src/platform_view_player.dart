import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'messages.g.dart';

/// A widget that displays a VAP player using a native platform view.
class PlatformViewPlayer extends StatelessWidget {
  /// Creates a new instance of [PlatformViewPlayer].
  const PlatformViewPlayer({super.key, required this.playerId});

  /// The ID of the player.
  final int playerId;

  @override
  Widget build(BuildContext context) {
    const String viewType = 'app.misi/vap_player_android';
    final PlatformVapViewCreationParams creationParams =
        PlatformVapViewCreationParams(playerId: playerId);

    // Touches are passed through to the native view so VAPX resource-click
    // detection keeps working.
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory:
          (BuildContext context, PlatformViewController controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers:
                  const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            );
          },
      onCreatePlatformView: (PlatformViewCreationParams params) {
        return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: viewType,
            layoutDirection:
                Directionality.maybeOf(context) ?? TextDirection.ltr,
            creationParams: creationParams,
            creationParamsCodec: AndroidVapPlayerApi.pigeonChannelCodec,
            onFocus: () => params.onFocusChanged(true),
          )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
  }
}
