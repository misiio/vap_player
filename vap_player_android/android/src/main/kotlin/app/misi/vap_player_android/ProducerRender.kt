package app.misi.vap_player_android

import android.opengl.GLES11Ext
import android.opengl.GLES20
import com.tencent.qgame.animplayer.AnimConfig
import com.tencent.qgame.animplayer.IRenderListener
import com.tencent.qgame.animplayer.PointRect
import com.tencent.qgame.animplayer.RenderConstant
import com.tencent.qgame.animplayer.YUVShader
import com.tencent.qgame.animplayer.util.ALog
import com.tencent.qgame.animplayer.util.GlFloatArray
import com.tencent.qgame.animplayer.util.ShaderUtil
import com.tencent.qgame.animplayer.util.TexCoordsUtil
import com.tencent.qgame.animplayer.util.VertexUtil
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.nio.FloatBuffer

/**
 * An [IRenderListener] that renders VAP frames into the [Surface][android.view.Surface]
 * of a Flutter [TextureRegistry.SurfaceProducer].
 *
 * VAP's `Decoder.prepareRender` builds its own renderer from
 * `IAnimView.getSurfaceTexture()`, which a SurfaceProducer cannot provide;
 * [TextureAnimView] therefore pre-sets this renderer on `Decoder.render`,
 * which `prepareRender` then keeps as-is.
 *
 * Ports both of VAP's renderers, selected at runtime:
 * - `Render` (hardware path): `HardDecoder` fetches [getExternalTexture] and
 *   feeds MediaCodec output through the returned OES texture.
 * - `YUVRender` (legacy fallback for version-1 files whose video width is not
 *   16-aligned): MediaCodec output arrives as planes via [setYUVData].
 *
 * All EGL/GL work is deferred to VAP's render thread — EGL contexts are bound
 * to the thread they are created on, and this object is constructed on the
 * main thread.
 */
internal class ProducerRender(
    private val producer: TextureRegistry.SurfaceProducer,
) : IRenderListener {

    companion object {
        private const val TAG = "VapPlayer.ProducerRender"
    }

    // Geometry shared by both program variants (filled without GL calls).
    private val vertexArray = GlFloatArray()
    private val alphaArray = GlFloatArray()
    private val rgbArray = GlFloatArray()
    private var surfaceSizeChanged = false
    private var surfaceWidth = 0
    private var surfaceHeight = 0

    private val egl = SurfaceEglHelper()
    private var eglReady = false

    /** Set off the render thread when the producer's Surface is replaced. */
    @Volatile
    private var surfaceInvalid = false

    private var rgb: RgbProgram? = null
    private var yuv: YuvProgram? = null

    /** Flips true once the decoder starts delivering YUV planes. */
    @Volatile
    private var yuvMode = false

    // Pending YUV frame: written by the decode thread in setYUVData, consumed
    // on the render thread in renderFrame (same handoff as VAP's YUVRender).
    private var widthYUV = 0
    private var heightYUV = 0
    private var yData: ByteBuffer? = null
    private var uData: ByteBuffer? = null
    private var vData: ByteBuffer? = null
    private var unpackAlign = 4

    // Producer size already applied; guards against redundant setSize calls.
    private var sizedWidth = 0
    private var sizedHeight = 0

    /**
     * Invalidates the EGL window surface so the next render-thread call
     * rebuilds it from a fresh `producer.getSurface()`. Needed after
     * `setSize` and after Flutter recycles the surface while the app is
     * backgrounded. The EGL context itself is kept, so GL objects survive.
     */
    fun markSurfaceInvalid() {
        surfaceInvalid = true
    }

    /**
     * Sizes the producer to the animation's display size. Render thread only.
     * Called from setAnimConfig — which VAP invokes even for version-1 files,
     * whose default config never reaches IAnimListener.onVideoConfigReady —
     * and from TextureAnimView.onConfigReady for the regular path.
     */
    fun ensureSurfaceSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        if (width == sizedWidth && height == sizedHeight) return
        sizedWidth = width
        sizedHeight = height
        // Resizing makes the producer hand out a new Surface.
        producer.setSize(width, height)
        markSurfaceInvalid()
    }

    /** Render thread only. Returns true when the EGL context is current. */
    private fun ensureEgl(): Boolean {
        val rebuild = surfaceInvalid
        if (rebuild) surfaceInvalid = false
        if (eglReady && !rebuild) return true
        val surface = try {
            producer.surface
        } catch (t: Throwable) {
            // The producer throws once released.
            ALog.e(TAG, "getSurface failed: $t")
            null
        } ?: return false
        val started = if (eglReady) egl.recreateSurface(surface) else egl.start(surface)
        if (!started) {
            teardownEgl()
            return false
        }
        eglReady = true
        // Default the viewport to the actual surface size; updateViewPort may
        // not have run yet (it is driven by onVideoConfigReady, which never
        // fires for version-1 default configs).
        GLES20.glViewport(0, 0, egl.surfaceWidth(), egl.surfaceHeight())
        return true
    }

    private fun teardownEgl() {
        if (eglReady) {
            rgb?.release()
            yuv?.release()
            egl.release()
        }
        // The GL programs died with their context either way.
        rgb = null
        yuv = null
        eglReady = false
    }

    override fun initRender() {
        // Programs are created lazily on first use; VAP only calls this from
        // its own renderers' constructors.
    }

    override fun renderFrame() {
        if (!ensureEgl()) return
        GLES20.glClearColor(0.0f, 0.0f, 0.0f, 0.0f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        if (surfaceSizeChanged && surfaceWidth > 0 && surfaceHeight > 0) {
            surfaceSizeChanged = false
            GLES20.glViewport(0, 0, surfaceWidth, surfaceHeight)
        }
        if (yuvMode) {
            drawYuv()
        } else {
            rgbProgram()?.draw(vertexArray, alphaArray, rgbArray)
        }
    }

    override fun clearFrame() {
        if (!eglReady) return
        GLES20.glClearColor(0.0f, 0.0f, 0.0f, 0.0f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        egl.swapBuffers()
    }

    override fun destroyRender() {
        teardownEgl()
    }

    override fun setAnimConfig(config: AnimConfig) {
        ensureSurfaceSize(config.width, config.height)
        // Decoder.preparePlay calls the plugins' onRenderCreate immediately
        // after setAnimConfig, before getExternalTexture. VAPX compiles its
        // shaders and uploads resource textures there, so its EGL context
        // must already be current on this render thread.
        check(ensureEgl()) { "Unable to initialize the VAP render surface" }
        vertexArray.setArray(
            VertexUtil.create(
                config.width,
                config.height,
                PointRect(0, 0, config.width, config.height),
                vertexArray.array,
            )
        )
        val alpha = TexCoordsUtil.create(
            config.videoWidth, config.videoHeight, config.alphaPointRect, alphaArray.array
        )
        val rgbCoords = TexCoordsUtil.create(
            config.videoWidth, config.videoHeight, config.rgbPointRect, rgbArray.array
        )
        alphaArray.setArray(alpha)
        rgbArray.setArray(rgbCoords)
    }

    override fun updateViewPort(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        surfaceSizeChanged = true
        surfaceWidth = width
        surfaceHeight = height
    }

    override fun getExternalTexture(): Int {
        if (!ensureEgl()) return 0
        return rgbProgram()?.textureId ?: 0
    }

    override fun releaseTexture() {
        rgb?.release()
        yuv?.release()
        rgb = null
        yuv = null
    }

    override fun swapBuffers() {
        if (!eglReady) return
        egl.swapBuffers()
    }

    // Called from the decode thread on the legacy YUV path; must not touch GL.
    override fun setYUVData(width: Int, height: Int, y: ByteArray?, u: ByteArray?, v: ByteArray?) {
        widthYUV = width
        heightYUV = height
        yData = y?.let { ByteBuffer.wrap(it) }
        uData = u?.let { ByteBuffer.wrap(it) }
        vData = v?.let { ByteBuffer.wrap(it) }
        // Plane rows are tightly packed; the default 4-byte unpack alignment
        // overreads the last row when the chroma width is not 4-aligned.
        if ((width / 2) % 4 != 0) {
            unpackAlign = if ((width / 2) % 2 == 0) 2 else 1
        }
        yuvMode = true
    }

    private fun rgbProgram(): RgbProgram? {
        rgb?.let { return it }
        return try {
            RgbProgram().also { rgb = it }
        } catch (t: Throwable) {
            ALog.e(TAG, "rgb program error: $t", t)
            null
        }
    }

    private fun drawYuv() {
        val y = yData
        val u = uData
        val v = vData
        if (widthYUV <= 0 || heightYUV <= 0 || y == null || u == null || v == null) return
        val program = yuv ?: try {
            YuvProgram().also { yuv = it }
        } catch (t: Throwable) {
            ALog.e(TAG, "yuv program error: $t", t)
            return
        }
        program.draw(vertexArray, alphaArray, rgbArray, widthYUV, heightYUV, y, u, v, unpackAlign)
        yData = null
        uData = null
        vData = null
    }
}

/** GL program for the hardware path; port of [com.tencent.qgame.animplayer.Render]. */
private class RgbProgram {

    private val shaderProgram =
        ShaderUtil.createProgram(RenderConstant.VERTEX_SHADER, RenderConstant.FRAGMENT_SHADER)
    private val uTextureLocation = GLES20.glGetUniformLocation(shaderProgram, "texture")
    private val aPositionLocation = GLES20.glGetAttribLocation(shaderProgram, "vPosition")
    private val aTextureAlphaLocation =
        GLES20.glGetAttribLocation(shaderProgram, "vTexCoordinateAlpha")
    private val aTextureRgbLocation =
        GLES20.glGetAttribLocation(shaderProgram, "vTexCoordinateRgb")
    private val genTexture = IntArray(1)

    init {
        GLES20.glGenTextures(genTexture.size, genTexture, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, genTexture[0])
        GLES20.glTexParameterf(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_NEAREST.toFloat(),
        )
        GLES20.glTexParameterf(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR.toFloat(),
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
    }

    val textureId: Int
        get() = genTexture[0]

    fun draw(vertexArray: GlFloatArray, alphaArray: GlFloatArray, rgbArray: GlFloatArray) {
        GLES20.glUseProgram(shaderProgram)
        vertexArray.setVertexAttribPointer(aPositionLocation)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, genTexture[0])
        GLES20.glUniform1i(uTextureLocation, 0)
        alphaArray.setVertexAttribPointer(aTextureAlphaLocation)
        rgbArray.setVertexAttribPointer(aTextureRgbLocation)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    fun release() {
        GLES20.glDeleteTextures(genTexture.size, genTexture, 0)
    }
}

/** GL program for the legacy YUV path; port of [com.tencent.qgame.animplayer.YUVRender]. */
private class YuvProgram {

    companion object {
        private val YUV_OFFSET = floatArrayOf(0f, -0.501960814f, -0.501960814f)
        private val YUV_MATRIX = floatArrayOf(
            1f, 1f, 1f,
            0f, -0.3441f, 1.772f,
            1.402f, -0.7141f, 0f,
        )
    }

    private val shaderProgram =
        ShaderUtil.createProgram(YUVShader.VERTEX_SHADER, YUVShader.FRAGMENT_SHADER)
    private val avPosition = GLES20.glGetAttribLocation(shaderProgram, "v_Position")
    private val rgbPosition = GLES20.glGetAttribLocation(shaderProgram, "vTexCoordinateRgb")
    private val alphaPosition = GLES20.glGetAttribLocation(shaderProgram, "vTexCoordinateAlpha")
    private val samplerY = GLES20.glGetUniformLocation(shaderProgram, "sampler_y")
    private val samplerU = GLES20.glGetUniformLocation(shaderProgram, "sampler_u")
    private val samplerV = GLES20.glGetUniformLocation(shaderProgram, "sampler_v")
    private val convertMatrixUniform = GLES20.glGetUniformLocation(shaderProgram, "convertMatrix")
    private val convertOffsetUniform = GLES20.glGetUniformLocation(shaderProgram, "offset")
    private val genTexture = IntArray(3)

    init {
        GLES20.glGenTextures(genTexture.size, genTexture, 0)
        for (id in genTexture) {
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_REPEAT)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_REPEAT)
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR
            )
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR
            )
        }
    }

    fun draw(
        vertexArray: GlFloatArray,
        alphaArray: GlFloatArray,
        rgbArray: GlFloatArray,
        width: Int,
        height: Int,
        y: ByteBuffer,
        u: ByteBuffer,
        v: ByteBuffer,
        unpackAlign: Int,
    ) {
        GLES20.glUseProgram(shaderProgram)
        vertexArray.setVertexAttribPointer(avPosition)
        alphaArray.setVertexAttribPointer(alphaPosition)
        rgbArray.setVertexAttribPointer(rgbPosition)

        GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, unpackAlign)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, genTexture[0])
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_LUMINANCE, width, height, 0,
            GLES20.GL_LUMINANCE, GLES20.GL_UNSIGNED_BYTE, y,
        )
        GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, genTexture[1])
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_LUMINANCE, width / 2, height / 2, 0,
            GLES20.GL_LUMINANCE, GLES20.GL_UNSIGNED_BYTE, u,
        )
        GLES20.glActiveTexture(GLES20.GL_TEXTURE2)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, genTexture[2])
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_LUMINANCE, width / 2, height / 2, 0,
            GLES20.GL_LUMINANCE, GLES20.GL_UNSIGNED_BYTE, v,
        )

        GLES20.glUniform1i(samplerY, 0)
        GLES20.glUniform1i(samplerU, 1)
        GLES20.glUniform1i(samplerV, 2)
        GLES20.glUniform3fv(convertOffsetUniform, 1, FloatBuffer.wrap(YUV_OFFSET))
        GLES20.glUniformMatrix3fv(convertMatrixUniform, 1, false, YUV_MATRIX, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(avPosition)
        GLES20.glDisableVertexAttribArray(rgbPosition)
        GLES20.glDisableVertexAttribArray(alphaPosition)
    }

    fun release() {
        GLES20.glDeleteTextures(genTexture.size, genTexture, 0)
    }
}
