package app.misi.vap_player_android

import android.content.Context
import android.view.View
import com.tencent.qgame.animplayer.AnimView
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class VapPlatformViewFactory(
    private val playerLookup: (Long) -> VapPlayerInstance?,
) : PlatformViewFactory(VapPlayerAndroidPlugin.pigeonCodec) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as PlatformVapViewCreationParams
        val instance = playerLookup(params.playerId)
            ?: throw IllegalStateException(
                "No VAP player found for id ${params.playerId}"
            )
        return VapPlatformView(context, instance)
    }
}

class VapPlatformView(
    context: Context,
    private val instance: VapPlayerInstance,
) : PlatformView {

    private val animView = AnimView(context)

    init {
        instance.attachView(animView)
    }

    override fun getView(): View = animView

    override fun dispose() {
        instance.detachView(animView)
    }
}
