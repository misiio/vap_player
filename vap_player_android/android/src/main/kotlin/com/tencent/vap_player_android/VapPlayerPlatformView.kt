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
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

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
    private const val NETWORK_ERROR_CODE: Long = -1L
    private const val NETWORK_AUTO_EVICT_MAX_BYTES: Long = 100L * 1024L * 1024L
  }

  private val mainHandler = Handler(Looper.getMainLooper())
  private val networkExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private val playbackRequestLock = Any()
  private val animView: AnimView = AnimView(context)
  private var frameEventsEnabled: Boolean = false
  private var tagValues: Map<String, String> = emptyMap()
  private var playbackRequestToken: Long = 0L
  private var activeDownloadConnection: HttpURLConnection? = null
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
    invalidatePendingNetworkPlayback()
    runOnMain {
      animView.stopPlay()
      animView.setAnimListener(null)
      animView.setFetchResource(null)
      animView.setOnResourceClickListener(null)
      onViewDisposed(viewId)
    }
    networkExecutor.shutdownNow()
  }

  fun play(request: VapPlayRequestMessage) {
    val source = request.source
    if (source.isNullOrEmpty()) {
      throw FlutterError("invalid-args", "play requires a non-empty source", null)
    }

    frameEventsEnabled = request.frameEventsEnabled ?: false
    tagValues = sanitizeTagValues(request.tagValues)
    val requestToken = invalidatePendingNetworkPlayback()

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
    }

    when (request.sourceType ?: VapSourceTypeMessage.FILE) {
      VapSourceTypeMessage.ASSET -> {
        runOnMain {
          if (!isRequestTokenCurrent(requestToken)) {
            return@runOnMain
          }
          val assetsPath = if (request.assetPackage.isNullOrEmpty()) {
            flutterAssets.getAssetFilePathByName(source)
          } else {
            flutterAssets.getAssetFilePathByName(source, request.assetPackage)
          }
          animView.startPlay(context.assets, assetsPath)
        }
      }

      VapSourceTypeMessage.FILE -> {
        runOnMain {
          if (!isRequestTokenCurrent(requestToken)) {
            return@runOnMain
          }
          animView.startPlay(File(source))
        }
      }

      VapSourceTypeMessage.NETWORK -> {
        playNetworkSource(source, requestToken)
      }
    }
  }

  fun stop() {
    invalidatePendingNetworkPlayback()
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
    runOnMain {
      eventApi.onPlaybackEvent(message) { result ->
        result.exceptionOrNull()?.let {
          Log.w(TAG, "onPlaybackEvent send failed: $it")
        }
      }
    }
  }

  private fun sendResourceClick(message: VapResourceClickEventMessage) {
    runOnMain {
      eventApi.onResourceClick(message) { result ->
        result.exceptionOrNull()?.let {
          Log.w(TAG, "onResourceClick send failed: $it")
        }
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

  private fun playNetworkSource(source: String, requestToken: Long) {
    if (!VapNetworkCacheUtils.isSupportedNetworkUrl(source)) {
      emitNetworkFailure("Invalid network URL: $source")
      return
    }

    val cacheFile = VapNetworkCacheUtils.cacheFileForUrl(context.cacheDir, source)
    if (cacheFile.isFile && cacheFile.length() > 0L) {
      VapNetworkCacheUtils.touch(cacheFile)
      runOnMain {
        if (isRequestTokenCurrent(requestToken)) {
          animView.startPlay(cacheFile)
        }
      }
      return
    }

    networkExecutor.execute {
      downloadNetworkSource(source = source, targetFile = cacheFile, requestToken = requestToken)
    }
  }

  private fun downloadNetworkSource(source: String, targetFile: File, requestToken: Long) {
    var connection: HttpURLConnection? = null
    val tempFile = File(
      targetFile.parentFile ?: context.cacheDir,
      "${targetFile.name}.download.$requestToken",
    )
    try {
      targetFile.parentFile?.mkdirs()
      if (tempFile.exists()) {
        tempFile.delete()
      }

      connection = (URL(source).openConnection() as HttpURLConnection).apply {
        requestMethod = "GET"
        instanceFollowRedirects = true
        connectTimeout = 15000
        readTimeout = 30000
        doInput = true
      }
      setActiveDownloadConnection(connection, requestToken)
      connection.connect()

      val responseCode = connection.responseCode
      if (responseCode !in 200..299) {
        throw IOException("Network request failed with status $responseCode")
      }

      connection.inputStream.use { input ->
        tempFile.outputStream().use { output ->
          input.copyTo(output)
        }
      }

      clearActiveDownloadConnection(connection)

      if (!isRequestTokenCurrent(requestToken)) {
        tempFile.delete()
        return
      }
      if (tempFile.length() <= 0L) {
        throw IOException("Downloaded file is empty")
      }

      if (targetFile.exists() && !targetFile.delete()) {
        throw IOException("Unable to replace cached file at ${targetFile.absolutePath}")
      }
      if (!tempFile.renameTo(targetFile)) {
        tempFile.copyTo(targetFile, overwrite = true)
        tempFile.delete()
      }
      VapNetworkCacheUtils.touch(targetFile)
      try {
        VapNetworkCacheUtils.pruneNetworkCacheToBytes(
          cacheRoot = context.cacheDir,
          maxBytes = NETWORK_AUTO_EVICT_MAX_BYTES,
          protectedFile = targetFile,
        )
      } catch (t: Throwable) {
        Log.w(TAG, "Failed to prune network cache: ${t.message ?: t.javaClass.simpleName}")
      }

      if (!isRequestTokenCurrent(requestToken)) {
        return
      }

      runOnMain {
        if (isRequestTokenCurrent(requestToken)) {
          animView.startPlay(targetFile)
        }
      }
    } catch (t: Throwable) {
      clearActiveDownloadConnection(connection)
      tempFile.delete()
      if (isRequestTokenCurrent(requestToken)) {
        emitNetworkFailure("Failed to load network source: ${t.message ?: t.javaClass.simpleName}")
      }
    } finally {
      connection?.disconnect()
      clearActiveDownloadConnection(connection)
    }
  }

  private fun emitNetworkFailure(message: String) {
    sendPlaybackEvent(
      VapPlaybackEventMessage(
        viewId = viewId,
        type = VapPlaybackEventTypeMessage.FAILED,
        errorCode = NETWORK_ERROR_CODE,
        errorMessage = message,
      ),
    )
  }

  private fun invalidatePendingNetworkPlayback(): Long {
    synchronized(playbackRequestLock) {
      playbackRequestToken += 1L
      activeDownloadConnection?.disconnect()
      activeDownloadConnection = null
      return playbackRequestToken
    }
  }

  private fun isRequestTokenCurrent(requestToken: Long): Boolean {
    synchronized(playbackRequestLock) {
      return playbackRequestToken == requestToken
    }
  }

  private fun setActiveDownloadConnection(connection: HttpURLConnection, requestToken: Long) {
    synchronized(playbackRequestLock) {
      if (isRequestTokenCurrentLocked(requestToken)) {
        activeDownloadConnection?.disconnect()
        activeDownloadConnection = connection
      } else {
        connection.disconnect()
      }
    }
  }

  private fun clearActiveDownloadConnection(connection: HttpURLConnection?) {
    synchronized(playbackRequestLock) {
      if (activeDownloadConnection === connection) {
        activeDownloadConnection = null
      }
    }
  }

  private fun isRequestTokenCurrentLocked(requestToken: Long): Boolean {
    return playbackRequestToken == requestToken
  }
}

internal object VapNetworkCacheUtils {
  private const val NETWORK_CACHE_DIR = "vap_player/network"

  fun isSupportedNetworkUrl(source: String): Boolean {
    val uri = try {
      URI(source)
    } catch (_: Exception) {
      return false
    }
    if (!uri.isAbsolute) {
      return false
    }
    val scheme = uri.scheme?.lowercase() ?: return false
    return scheme == "http" || scheme == "https"
  }

  fun cacheFileForUrl(cacheRoot: File, url: String): File {
    val digest = MessageDigest.getInstance("SHA-256").digest(url.toByteArray(Charsets.UTF_8))
    val hex = digest.joinToString(separator = "") { byte -> "%02x".format(byte) }
    return File(cacheDirectory(cacheRoot), "$hex.mp4")
  }

  fun cacheDirectory(cacheRoot: File): File {
    return File(cacheRoot, NETWORK_CACHE_DIR)
  }

  fun networkCacheSizeBytes(cacheRoot: File): Long {
    val directory = cacheDirectory(cacheRoot)
    val files = directory.listFiles() ?: return 0L
    return files
      .filter { it.isFile }
      .sumOf { it.length() }
  }

  fun clearNetworkCache(cacheRoot: File) {
    val directory = cacheDirectory(cacheRoot)
    val files = directory.listFiles() ?: return
    files.forEach { file ->
      if (file.isDirectory) {
        file.deleteRecursively()
      } else {
        file.delete()
      }
    }
  }

  fun pruneNetworkCacheToBytes(cacheRoot: File, maxBytes: Long, protectedFile: File?) {
    require(maxBytes >= 0L) { "maxBytes must be >= 0" }

    val directory = cacheDirectory(cacheRoot)
    val files = directory.listFiles()
      ?.filter { it.isFile }
      ?.toMutableList()
      ?: return

    var totalSize = files.sumOf { it.length() }
    if (totalSize <= maxBytes) {
      return
    }

    val protectedCanonicalPath = protectedFile?.let(::canonicalOrAbsolutePath)
    files.sortBy { it.lastModified() }

    for (file in files) {
      if (totalSize <= maxBytes) {
        break
      }
      if (protectedCanonicalPath != null && canonicalOrAbsolutePath(file) == protectedCanonicalPath) {
        continue
      }
      val fileLength = file.length()
      if (file.delete()) {
        totalSize -= fileLength
      }
    }
  }

  fun touch(file: File) {
    if (!file.exists()) {
      return
    }
    file.setLastModified(System.currentTimeMillis())
  }

  private fun canonicalOrAbsolutePath(file: File): String {
    return try {
      file.canonicalPath
    } catch (_: IOException) {
      file.absolutePath
    }
  }
}
