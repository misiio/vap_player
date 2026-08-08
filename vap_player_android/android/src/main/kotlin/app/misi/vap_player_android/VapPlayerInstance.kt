package app.misi.vap_player_android

import android.os.Handler
import android.os.Looper
import com.tencent.qgame.animplayer.AnimConfig
import com.tencent.qgame.animplayer.AnimView
import com.tencent.qgame.animplayer.IAnimView
import com.tencent.qgame.animplayer.inter.IAnimListener
import com.tencent.qgame.animplayer.inter.OnResourceClickListener
import com.tencent.qgame.animplayer.mix.Resource
import com.tencent.qgame.animplayer.util.ScaleType
import io.flutter.plugin.common.BinaryMessenger
import java.io.File

/**
 * A single VAP player: bridges one Dart-side controller to a native
 * [IAnimView], forwarding commands in and events out.
 *
 * In texture mode the view is a [TextureAnimView] created at construction.
 * In platform-view mode the [AnimView] is attached later, when the Flutter
 * platform view is created; commands issued before that are queued.
 */
class VapPlayerInstance(
    private val playerId: Long,
    private val messenger: BinaryMessenger,
    flutterApi: VapResourceFlutterApi,
    private val creationOptions: PlatformCreationOptions,
    private val textureView: TextureAnimView?,
) : VapPlayerInstanceApi, IAnimListener, OnResourceClickListener {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val eventSink = QueuingEventSink<PlatformVapEvent>()

    private var animView: IAnimView? = textureView
    private var hasResourceDelegate = false
    private var pendingPlay: PlatformPlayOptions? = null
    private var mute = false
    private var repeatCount = 0L

    private val fetchBridge = FetchResourceBridge(
        playerId,
        flutterApi,
        mainHandler,
    ) { hasResourceDelegate }

    init {
        VapPlayerInstanceApi.setUp(messenger, this, playerId.toString())
        VapEventsStreamHandler.register(
            messenger,
            object : VapEventsStreamHandler() {
                override fun onListen(
                    p0: Any?,
                    sink: PigeonEventSink<PlatformVapEvent>
                ) {
                    eventSink.setDelegate(sink)
                }

                override fun onCancel(p0: Any?) {
                    eventSink.setDelegate(null)
                }
            },
            playerId.toString(),
        )
        textureView?.let { configureView(it) }
    }

    /** Platform-view mode: called when the Flutter platform view is created. */
    fun attachView(view: AnimView) {
        animView = view
        configureView(view)
        view.setMute(mute)
        pendingPlay?.let { options ->
            pendingPlay = null
            doPlay(view, options)
        }
    }

    /** Platform-view mode: called when the Flutter platform view is disposed. */
    fun detachView(view: AnimView) {
        if (animView === view) {
            view.stopPlay()
            animView = null
        }
    }

    private fun configureView(view: IAnimView) {
        view.setAnimListener(this)
        view.setFetchResource(fetchBridge)
        view.setOnResourceClickListener(this)
    }

    fun dispose() {
        pendingPlay = null
        animView?.setAnimListener(null)
        animView?.stopPlay()
        textureView?.destroy()
        animView = null
        eventSink.endOfStream()
        VapPlayerInstanceApi.setUp(messenger, null, playerId.toString())
    }

    // ------------------------------------------------------------------
    // VapPlayerInstanceApi (called from Dart on the platform thread)
    // ------------------------------------------------------------------

    override fun play(options: PlatformPlayOptions) {
        mute = options.mute
        repeatCount = options.repeatCount
        val view = animView
        if (view == null) {
            // Platform view not created yet; start once it attaches.
            pendingPlay = options
            return
        }
        doPlay(view, options)
    }

    private fun doPlay(view: IAnimView, options: PlatformPlayOptions) {
        view.setLoop(toNativeLoop(options.repeatCount))
        view.setMute(options.mute)
        options.fps?.let { view.setFps(it.toInt()) }
        // enableVersion1 is not part of IAnimView, so each implementation
        // exposes it separately.
        when (view) {
            is AnimView -> view.enableVersion1(options.enableOldVersion)
            is TextureAnimView -> view.enableVersion1(options.enableOldVersion)
        }
        (view as? AnimView)?.setScaleType(options.scaleType.toNative())
        view.startPlay(File(options.path))
    }

    override fun stop() {
        pendingPlay = null
        animView?.stopPlay()
    }

    override fun setMute(mute: Boolean) {
        this.mute = mute
        animView?.setMute(mute)
    }

    override fun setRepeatCount(repeatCount: Long) {
        this.repeatCount = repeatCount
        animView?.setLoop(toNativeLoop(repeatCount))
    }

    override fun setHasResourceDelegate(hasDelegate: Boolean) {
        hasResourceDelegate = hasDelegate
    }

    // ------------------------------------------------------------------
    // IAnimListener (called on VAP worker threads)
    // ------------------------------------------------------------------

    override fun onVideoConfigReady(config: AnimConfig): Boolean {
        textureView?.onConfigReady(config)
        sendEvent(
            ConfigReadyEvent(
                width = config.width.toLong(),
                height = config.height.toLong(),
                videoWidth = config.videoWidth.toLong(),
                videoHeight = config.videoHeight.toLong(),
                frameCount = config.totalFrames.toLong(),
                fps = config.fps.toLong(),
                isMix = config.isMix,
            )
        )
        return true
    }

    override fun onVideoStart() {
        sendEvent(StartedEvent())
    }

    override fun onVideoRender(frameIndex: Int, config: AnimConfig?) {
        if (creationOptions.enableFrameEvents) {
            sendEvent(FrameRenderedEvent(frameIndex.toLong()))
        }
    }

    override fun onVideoComplete() {
        sendEvent(CompletedEvent())
    }

    override fun onVideoDestroy() {
        sendEvent(DestroyedEvent())
    }

    override fun onFailed(errorType: Int, errorMsg: String?) {
        sendEvent(FailedEvent(errorType.toLong(), errorMsg))
    }

    // ------------------------------------------------------------------
    // OnResourceClickListener (called on the UI thread by MixAnimPlugin)
    // ------------------------------------------------------------------

    override fun onClick(resource: Resource) {
        sendEvent(ResourceClickedEvent(resource.toPlatform()))
    }

    private fun sendEvent(event: PlatformVapEvent) {
        mainHandler.post { eventSink.success(event) }
    }

    private fun toNativeLoop(repeatCount: Long): Int = when {
        repeatCount < 0 -> Int.MAX_VALUE
        else -> repeatCount.toInt() + 1
    }
}

private fun PlatformScaleType.toNative(): ScaleType = when (this) {
    PlatformScaleType.FIT_XY -> ScaleType.FIT_XY
    PlatformScaleType.FIT_CENTER -> ScaleType.FIT_CENTER
    PlatformScaleType.CENTER_CROP -> ScaleType.CENTER_CROP
}
