package app.misi.vap_player_android

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MessageCodec

/** Android implementation of the vap_player plugin. */
class VapPlayerAndroidPlugin : FlutterPlugin, AndroidVapPlayerApi {

    companion object {
        const val PLATFORM_VIEW_TYPE = "app.misi/vap_player_android"

        val pigeonCodec: MessageCodec<Any?>
            get() = AndroidVapPlayerApi.codec
    }

    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var flutterApi: VapResourceFlutterApi? = null
    private val players = mutableMapOf<Long, VapPlayerInstance>()
    private var nextPlayerId = 1L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        flutterApi = VapResourceFlutterApi(binding.binaryMessenger)
        AndroidVapPlayerApi.setUp(binding.binaryMessenger, this)
        binding.platformViewRegistry.registerViewFactory(
            PLATFORM_VIEW_TYPE,
            VapPlatformViewFactory { playerId -> players[playerId] },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disposeAllPlayers()
        AndroidVapPlayerApi.setUp(binding.binaryMessenger, null)
        flutterApi = null
        this.binding = null
    }

    private fun disposeAllPlayers() {
        players.values.forEach { it.dispose() }
        players.clear()
    }

    // ------------------------------------------------------------------
    // AndroidVapPlayerApi
    // ------------------------------------------------------------------

    override fun initialize() {
        disposeAllPlayers()
    }

    override fun createForPlatformView(options: PlatformCreationOptions): Long {
        val binding = requireBinding()
        val playerId = nextPlayerId++
        players[playerId] = VapPlayerInstance(
            playerId,
            binding.binaryMessenger,
            requireNotNull(flutterApi),
            options,
            textureView = null,
        )
        return playerId
    }

    override fun createForTextureView(
        options: PlatformCreationOptions
    ): TexturePlayerIds {
        val binding = requireBinding()
        val producer = binding.textureRegistry.createSurfaceProducer()
        val playerId = nextPlayerId++
        players[playerId] = VapPlayerInstance(
            playerId,
            binding.binaryMessenger,
            requireNotNull(flutterApi),
            options,
            textureView = TextureAnimView(producer),
        )
        return TexturePlayerIds(playerId = playerId, textureId = producer.id())
    }

    override fun dispose(playerId: Long) {
        players.remove(playerId)?.dispose()
    }

    private fun requireBinding(): FlutterPlugin.FlutterPluginBinding =
        binding ?: throw IllegalStateException("Plugin not attached to engine")
}
