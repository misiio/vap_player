package com.tencent.vap_player_android

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class VapPlayerPlatformViewFactory(
  private val flutterAssets: FlutterPlugin.FlutterAssets,
  private val eventApi: VapEventApi,
  private val resourceApi: VapResourceApi,
  private val onViewDisposed: (Long) -> Unit,
  private val onViewCreated: (VapPlayerPlatformView) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val view = VapPlayerPlatformView(
      context = context,
      viewId = viewId.toLong(),
      flutterAssets = flutterAssets,
      eventApi = eventApi,
      resourceApi = resourceApi,
      onViewDisposed = onViewDisposed,
    )
    onViewCreated(view)
    return view
  }
}
