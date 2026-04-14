package com.tencent.vap_player_android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.tencent.qgame.animplayer.AnimConfig
import com.tencent.qgame.animplayer.AnimView
import com.tencent.qgame.animplayer.inter.IAnimListener
import com.tencent.qgame.animplayer.inter.IFetchResource
import com.tencent.qgame.animplayer.inter.OnResourceClickListener
import com.tencent.qgame.animplayer.mix.Resource
import com.tencent.qgame.animplayer.util.ScaleType
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.platform.PlatformView
import java.io.File

class VapPlayerPlatformView(
  private val context: Context,
  val viewId: Long,
  private val flutterAssets: FlutterPlugin.FlutterAssets,
  private val eventApi: VapEventApi,
  private val resourceApi: VapResourceApi,
  private val onViewDisposed: (Long) -> Unit,
) : PlatformView, IAnimListener {

  companion object {
    const val VIEW_TYPE: String = "vap_player/view"
    private const val TAG: String = "VapPlayerPlatformView"
  }

  private val mainHandler = Handler(Looper.getMainLooper())
  private val animView: AnimView = AnimView(context)
  private var frameEventsEnabled: Boolean = false
  private var tagValues: Map<String, String> = emptyMap()
  private var released: Boolean = false

  private val clickListener = object : OnResourceClickListener {
    override fun onClick(resource: Resource) {
      val point = resource.curPoint
      sendResourceClick(
        VapResourceClickEventMessage(
          viewId = viewId,
          resourceId = resource.id,
          tag = resource.tag,
          x = point?.x?.toDouble(),
          y = point?.y?.toDouble(),
          width = point?.w?.toDouble(),
          height = point?.h?.toDouble(),
        ),
      )
    }
  }

  private val fetchResource = object : IFetchResource {
    override fun fetchImage(resource: Resource, result: (Bitmap?) -> Unit) {
      val request = VapImageResolveRequestMessage(
        viewId = viewId,
        resourceId = resource.id,
        tag = resource.tag,
        type = resource.type.type,
        loadType = resource.loadType.type,
        width = (resource.curPoint?.w ?: 0).toLong(),
        height = (resource.curPoint?.h ?: 0).toLong(),
        url = tagValues[resource.tag],
      )

      resourceApi.resolveImage(request) { response ->
        if (response.isFailure) {
          Log.w(TAG, "resolveImage failed: ${response.exceptionOrNull()}")
          result(null)
          return@resolveImage
        }
        val payload = response.getOrNull()
        val bytes = payload?.imageBytes
        if (bytes == null || bytes.isEmpty()) {
          result(null)
          return@resolveImage
        }

        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        result(bitmap)
      }
    }

    override fun fetchText(resource: Resource, result: (String?) -> Unit) {
      result(tagValues[resource.tag])
    }

    override fun releaseResource(resources: List<Resource>) {
      resources.forEach { resource ->
        resource.bitmap?.takeIf { !it.isRecycled }?.recycle()
      }
    }
  }

  init {
    runOnMain {
      animView.setAnimListener(this)
      animView.setFetchResource(fetchResource)
      animView.setOnResourceClickListener(clickListener)
      animView.setScaleType(ScaleType.FIT_XY)
    }
  }

  override fun getView(): AnimView {
    return animView
  }

  override fun dispose() {
    release()
  }

  fun release() {
    if (released) {
      return
    }
    released = true
    runOnMain {
      animView.stopPlay()
      animView.setAnimListener(null)
      animView.setFetchResource(null)
      animView.setOnResourceClickListener(null)
      onViewDisposed(viewId)
    }
  }

  fun play(request: VapPlayRequestMessage) {
    val source = request.source
    if (source.isNullOrEmpty()) {
      throw FlutterError("invalid-args", "play requires a non-empty source", null)
    }

    frameEventsEnabled = request.frameEventsEnabled ?: false
    tagValues = sanitizeTagValues(request.tagValues)

    runOnMain {
      animView.setMute(request.mute ?: false)

      val contentMode = request.contentMode ?: VapContentModeMessage.SCALE_TO_FILL
      setContentMode(contentMode)

      val fps = (request.fps ?: 0L).toInt()
      if (fps > 0) {
        animView.setFps(fps)
      }

      val repeatCount = request.repeatCount ?: 0L
      val loop = if (repeatCount < 0L) Int.MAX_VALUE else (repeatCount + 1L).toInt()
      animView.setLoop(loop)

      when (request.sourceType ?: VapSourceTypeMessage.FILE) {
        VapSourceTypeMessage.ASSET -> {
          val assetsPath = if (request.assetPackage.isNullOrEmpty()) {
            flutterAssets.getAssetFilePathByName(source)
          } else {
            flutterAssets.getAssetFilePathByName(source, request.assetPackage)
          }
          animView.startPlay(context.assets, assetsPath)
        }

        VapSourceTypeMessage.FILE -> {
          animView.startPlay(File(source))
        }
      }
    }
  }

  fun stop() {
    runOnMain {
      animView.stopPlay()
      sendPlaybackEvent(
        VapPlaybackEventMessage(
          viewId = viewId,
          type = VapPlaybackEventTypeMessage.STOPPED,
        ),
      )
    }
  }

  fun setMute(mute: Boolean) {
    runOnMain {
      animView.setMute(mute)
    }
  }

  fun setContentMode(mode: VapContentModeMessage) {
    runOnMain {
      when (mode) {
        VapContentModeMessage.SCALE_TO_FILL -> animView.setScaleType(ScaleType.FIT_XY)
        VapContentModeMessage.ASPECT_FIT -> animView.setScaleType(ScaleType.FIT_CENTER)
        VapContentModeMessage.ASPECT_FILL -> animView.setScaleType(ScaleType.CENTER_CROP)
      }
    }
  }

  fun setFrameEventsEnabled(enabled: Boolean) {
    frameEventsEnabled = enabled
  }

  override fun onVideoConfigReady(config: AnimConfig): Boolean {
    sendPlaybackEvent(
      VapPlaybackEventMessage(
        viewId = viewId,
        type = VapPlaybackEventTypeMessage.CONFIG_READY,
        width = config.width.toLong(),
        height = config.height.toLong(),
        fps = config.fps.toLong(),
        isMix = config.isMix,
      ),
    )
    return true
  }

  override fun onVideoStart() {
    sendPlaybackEvent(
      VapPlaybackEventMessage(
        viewId = viewId,
        type = VapPlaybackEventTypeMessage.START,
      ),
    )
  }

  override fun onVideoRender(frameIndex: Int, config: AnimConfig?) {
    if (!frameEventsEnabled) {
      return
    }
    sendPlaybackEvent(
      VapPlaybackEventMessage(
        viewId = viewId,
        type = VapPlaybackEventTypeMessage.FRAME,
        frameIndex = frameIndex.toLong(),
      ),
    )
  }

  override fun onVideoComplete() {
    sendPlaybackEvent(
      VapPlaybackEventMessage(
        viewId = viewId,
        type = VapPlaybackEventTypeMessage.COMPLETE,
      ),
    )
  }

  override fun onVideoDestroy() {
    sendPlaybackEvent(
      VapPlaybackEventMessage(
        viewId = viewId,
        type = VapPlaybackEventTypeMessage.DESTROY,
      ),
    )
  }

  override fun onFailed(errorType: Int, errorMsg: String?) {
    sendPlaybackEvent(
      VapPlaybackEventMessage(
        viewId = viewId,
        type = VapPlaybackEventTypeMessage.FAILED,
        errorCode = errorType.toLong(),
        errorMessage = errorMsg,
      ),
    )
  }

  private fun sendPlaybackEvent(message: VapPlaybackEventMessage) {
    eventApi.onPlaybackEvent(message) { result ->
      result.exceptionOrNull()?.let {
        Log.w(TAG, "onPlaybackEvent send failed: $it")
      }
    }
  }

  private fun sendResourceClick(message: VapResourceClickEventMessage) {
    eventApi.onResourceClick(message) { result ->
      result.exceptionOrNull()?.let {
        Log.w(TAG, "onResourceClick send failed: $it")
      }
    }
  }

  private fun sanitizeTagValues(input: Map<String?, String?>?): Map<String, String> {
    if (input.isNullOrEmpty()) {
      return emptyMap()
    }
    return input.entries
      .filter { entry -> entry.key != null && entry.value != null }
      .associate { entry -> entry.key!! to entry.value!! }
  }

  private fun runOnMain(action: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) {
      action()
    } else {
      mainHandler.post(action)
    }
  }
}
