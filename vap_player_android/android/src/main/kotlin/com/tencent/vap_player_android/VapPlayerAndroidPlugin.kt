package com.tencent.vap_player_android

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin

class VapPlayerAndroidPlugin : FlutterPlugin, VapHostApi {
  private lateinit var applicationContext: Context
  private lateinit var flutterAssets: FlutterPlugin.FlutterAssets
  private lateinit var eventApi: VapEventApi
  private lateinit var resourceApi: VapResourceApi

  private val platformViews = mutableMapOf<Long, VapPlayerPlatformView>()

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = binding.applicationContext
    flutterAssets = binding.flutterAssets
    eventApi = VapEventApi(binding.binaryMessenger)
    resourceApi = VapResourceApi(binding.binaryMessenger)

    VapHostApi.setUp(binding.binaryMessenger, this)
    binding.platformViewRegistry.registerViewFactory(
      VapPlayerPlatformView.VIEW_TYPE,
      VapPlayerPlatformViewFactory(
        flutterAssets = flutterAssets,
        eventApi = eventApi,
        resourceApi = resourceApi,
        onViewDisposed = ::onViewDisposed,
        onViewCreated = { view -> platformViews[view.viewId] = view },
      ),
    )
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    VapHostApi.setUp(binding.binaryMessenger, null)
    platformViews.values.forEach { it.release() }
    platformViews.clear()
  }

  override fun play(request: VapPlayRequestMessage) {
    val viewId = request.viewId
      ?: throw FlutterError("invalid-args", "play requires a non-null viewId", null)
    val view = requireView(viewId)
    view.play(request)
  }

  override fun stop(viewId: Long) {
    requireView(viewId).stop()
  }

  override fun setMute(viewId: Long, mute: Boolean) {
    requireView(viewId).setMute(mute)
  }

  override fun setContentMode(viewId: Long, mode: VapContentModeMessage) {
    requireView(viewId).setContentMode(mode)
  }

  override fun setFrameEventsEnabled(viewId: Long, enabled: Boolean) {
    requireView(viewId).setFrameEventsEnabled(enabled)
  }

  override fun dispose(viewId: Long) {
    requireView(viewId).release()
    platformViews.remove(viewId)
  }

  override fun getNetworkCacheSizeBytes(callback: (Result<Long>) -> Unit) {
    try {
      callback(Result.success(VapNetworkCacheUtils.networkCacheSizeBytes(applicationContext.cacheDir)))
    } catch (t: Throwable) {
      callback(Result.failure(t))
    }
  }

  override fun clearNetworkCache() {
    VapNetworkCacheUtils.clearNetworkCache(applicationContext.cacheDir)
  }

  override fun pruneNetworkCacheToBytes(maxBytes: Long) {
    if (maxBytes < 0L) {
      throw FlutterError("invalid-args", "pruneNetworkCacheToBytes requires maxBytes >= 0", null)
    }
    VapNetworkCacheUtils.pruneNetworkCacheToBytes(
      cacheRoot = applicationContext.cacheDir,
      maxBytes = maxBytes,
      protectedFile = null,
    )
  }

  private fun requireView(viewId: Long): VapPlayerPlatformView {
    return platformViews[viewId]
      ?: throw FlutterError("not-found", "No VapView found for viewId=$viewId", null)
  }

  private fun onViewDisposed(viewId: Long) {
    platformViews.remove(viewId)
  }
}
