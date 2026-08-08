package app.misi.vap_player_android

import android.content.res.AssetManager
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import com.tencent.qgame.animplayer.AnimConfig
import com.tencent.qgame.animplayer.AnimPlayer
import com.tencent.qgame.animplayer.Constant
import com.tencent.qgame.animplayer.HardDecoder
import com.tencent.qgame.animplayer.IAnimView
import com.tencent.qgame.animplayer.file.AssetsFileContainer
import com.tencent.qgame.animplayer.file.FileContainer
import com.tencent.qgame.animplayer.file.IFileContainer
import com.tencent.qgame.animplayer.inter.IAnimListener
import com.tencent.qgame.animplayer.inter.IFetchResource
import com.tencent.qgame.animplayer.inter.OnResourceClickListener
import com.tencent.qgame.animplayer.mask.MaskConfig
import com.tencent.qgame.animplayer.util.IScaleType
import com.tencent.qgame.animplayer.util.ScaleType
import io.flutter.view.TextureRegistry
import java.io.File

/**
 * A headless [IAnimView] that renders into a Flutter
 * [TextureRegistry.SurfaceProducer] instead of an Android view hierarchy.
 *
 * A SurfaceProducer only exposes a [android.view.Surface], so [getSurfaceTexture]
 * returns null; instead a [ProducerRender] is pre-set on `Decoder.render`
 * before each play, which makes VAP's `Decoder.prepareRender` skip its own
 * SurfaceTexture-based renderer. All view-layout concerns (scale type, mask
 * layout) are handled on the Dart side in texture mode.
 */
class TextureAnimView(
    private val producer: TextureRegistry.SurfaceProducer,
) : IAnimView {

    private val player = AnimPlayer(this)
    private val uiHandler = Handler(Looper.getMainLooper())
    private var released = false
    private var producerRender: ProducerRender? = null

    init {
        player.isDetachedFromWindow = false
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                // Nothing to do: the EGL surface is rebuilt lazily from a
                // fresh producer surface on the next play.
            }

            override fun onSurfaceCleanup() {
                // The producer's Surface is about to be destroyed (e.g. the
                // app was backgrounded). VAP cannot resume mid-stream, so
                // stop and let the next play rebuild the EGL surface.
                player.stopPlay()
                producerRender?.markSurfaceInvalid()
            }
        })
    }

    /** Called from IAnimListener.onVideoConfigReady on the worker thread. */
    fun onConfigReady(config: AnimConfig) {
        if (released) return
        producerRender?.ensureSurfaceSize(config.width, config.height)
        player.onSurfaceTextureSizeChanged(config.width, config.height)
    }

    fun destroy() {
        released = true
        player.onSurfaceTextureDestroyed()
        producer.release()
    }

    override fun prepareTextureView() {
        uiHandler.post {
            if (!released) {
                player.onSurfaceTextureAvailable(0, 0)
            }
        }
    }

    // A SurfaceProducer has no SurfaceTexture; VAP never consults this
    // because Decoder.render is always pre-set in startPlay.
    override fun getSurfaceTexture(): SurfaceTexture? = null

    override fun startPlay(file: File) {
        try {
            startPlay(FileContainer(file))
        } catch (e: Throwable) {
            player.animListener?.onFailed(
                Constant.REPORT_ERROR_TYPE_FILE_ERROR,
                Constant.ERROR_MSG_FILE_ERROR
            )
            player.animListener?.onVideoComplete()
        }
    }

    override fun startPlay(assetManager: AssetManager, assetsPath: String) {
        try {
            startPlay(AssetsFileContainer(assetManager, assetsPath))
        } catch (e: Throwable) {
            player.animListener?.onFailed(
                Constant.REPORT_ERROR_TYPE_FILE_ERROR,
                Constant.ERROR_MSG_FILE_ERROR
            )
            player.animListener?.onVideoComplete()
        }
    }

    override fun startPlay(fileContainer: IFileContainer) {
        if (released) return
        injectProducerRender()
        player.startPlay(fileContainer)
    }

    /**
     * Pre-sets [ProducerRender] on the decoder so that Decoder.prepareRender
     * keeps it instead of requiring a SurfaceTexture. The decoder is created
     * here exactly as AnimPlayer.prepareDecoder would (that method is
     * null-guarded, so it leaves this instance in place). VAP nulls the
     * render when the decoder is destroyed, hence the re-check on every play.
     */
    private fun injectProducerRender() {
        val decoder = player.decoder ?: HardDecoder(player).apply {
            playLoop = player.playLoop
            fps = player.fps
        }.also { player.decoder = it }
        if (decoder.render == null) {
            decoder.render = ProducerRender(producer).also { producerRender = it }
        }
    }

    override fun stopPlay() {
        player.stopPlay()
    }

    override fun isRunning(): Boolean = player.isRunning()

    override fun setAnimListener(animListener: IAnimListener?) {
        player.animListener = animListener
    }

    override fun setFetchResource(fetchResource: IFetchResource?) {
        player.pluginManager.getMixAnimPlugin()?.resourceRequest = fetchResource
    }

    override fun setOnResourceClickListener(
        resourceClickListener: OnResourceClickListener?
    ) {
        player.pluginManager.getMixAnimPlugin()?.resourceClickListener =
            resourceClickListener
    }

    override fun setLoop(playLoop: Int) {
        player.playLoop = playLoop
    }

    /** Mirrors [com.tencent.qgame.animplayer.AnimView.enableVersion1]. */
    fun enableVersion1(enable: Boolean) {
        player.enableVersion1 = enable
    }

    override fun setFps(fps: Int) {
        player.defaultFps = fps
    }

    // Scale type operates on Android view layout params; in texture mode the
    // fit is applied by Flutter widgets instead.
    override fun setScaleType(type: ScaleType) {}

    override fun setScaleType(scaleType: IScaleType) {}

    override fun setMute(isMute: Boolean) {
        player.isMute = isMute
    }

    override fun supportMask(isSupport: Boolean, isEdgeBlur: Boolean) {
        player.supportMaskBoolean = isSupport
        player.maskEdgeBlurBoolean = isEdgeBlur
    }

    override fun updateMaskConfig(maskConfig: MaskConfig?) {
        player.updateMaskConfig(maskConfig)
    }

    override fun getRealSize(): Pair<Int, Int> {
        val config = player.configManager.config ?: return Pair(0, 0)
        return Pair(config.width, config.height)
    }
}
