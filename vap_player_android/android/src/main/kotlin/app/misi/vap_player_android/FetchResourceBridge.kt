package app.misi.vap_player_android

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import com.tencent.qgame.animplayer.inter.IFetchResource
import com.tencent.qgame.animplayer.mix.Resource
import com.tencent.qgame.animplayer.mix.Src
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridges VAP's [IFetchResource] to the Dart resource delegate via the
 * pigeon [VapResourceFlutterApi].
 *
 * VAP blocks playback until every `result` callback is invoked, so each
 * request is guarded by a timeout that resolves to null (empty slot).
 */
class FetchResourceBridge(
    private val playerId: Long,
    private val flutterApi: VapResourceFlutterApi,
    private val mainHandler: Handler,
    private val hasDelegate: () -> Boolean,
) : IFetchResource {

    companion object {
        private const val FETCH_TIMEOUT_MS = 5000L
    }

    private val fetchedBitmaps = mutableListOf<Bitmap>()

    override fun fetchImage(resource: Resource, result: (Bitmap?) -> Unit) {
        if (!hasDelegate()) {
            result(null)
            return
        }
        val done = AtomicBoolean(false)
        fun finish(bitmap: Bitmap?) {
            if (done.compareAndSet(false, true)) {
                if (bitmap != null) {
                    synchronized(fetchedBitmaps) { fetchedBitmaps.add(bitmap) }
                }
                result(bitmap)
            }
        }
        mainHandler.post {
            flutterApi.resolveImage(playerId, resource.toPlatform()) { reply ->
                val bytes = reply.getOrNull()
                finish(
                    bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                )
            }
        }
        mainHandler.postDelayed({ finish(null) }, FETCH_TIMEOUT_MS)
    }

    override fun fetchText(resource: Resource, result: (String?) -> Unit) {
        if (!hasDelegate()) {
            result(null)
            return
        }
        val done = AtomicBoolean(false)
        fun finish(text: String?) {
            if (done.compareAndSet(false, true)) {
                result(text)
            }
        }
        mainHandler.post {
            flutterApi.resolveText(playerId, resource.toPlatform()) { reply ->
                finish(reply.getOrNull())
            }
        }
        mainHandler.postDelayed({ finish(null) }, FETCH_TIMEOUT_MS)
    }

    override fun releaseResource(resources: List<Resource>) {
        synchronized(fetchedBitmaps) {
            fetchedBitmaps.forEach { if (!it.isRecycled) it.recycle() }
            fetchedBitmaps.clear()
        }
    }
}

fun Resource.toPlatform(): PlatformVapResource = PlatformVapResource(
    id = id,
    type = when (type) {
        Src.SrcType.IMG -> PlatformResourceType.IMAGE
        else -> PlatformResourceType.TEXT
    },
    tag = tag,
)
