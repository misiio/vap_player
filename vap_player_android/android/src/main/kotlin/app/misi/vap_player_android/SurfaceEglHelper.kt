package app.misi.vap_player_android

import android.opengl.EGL14
import android.view.Surface
import com.tencent.qgame.animplayer.util.ALog
import javax.microedition.khronos.egl.EGL10
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.egl.EGLContext
import javax.microedition.khronos.egl.EGLDisplay
import javax.microedition.khronos.egl.EGLSurface

/**
 * Port of VAP's [com.tencent.qgame.animplayer.EGLUtil] that targets an
 * [android.view.Surface] (obtained from a Flutter `SurfaceProducer`) instead
 * of a [android.graphics.SurfaceTexture].
 *
 * The Surface is owned by the producer and is never released here.
 */
internal class SurfaceEglHelper {

    companion object {
        private const val TAG = "VapPlayer.SurfaceEglHelper"
    }

    private var egl: EGL10? = null
    private var eglDisplay: EGLDisplay? = EGL10.EGL_NO_DISPLAY
    private var eglSurface: EGLSurface? = EGL10.EGL_NO_SURFACE
    private var eglContext: EGLContext? = EGL10.EGL_NO_CONTEXT
    private var eglConfig: EGLConfig? = null

    /**
     * Creates the EGL context and makes it current on the calling thread.
     * Returns true on success.
     */
    fun start(surface: Surface): Boolean {
        try {
            val egl = EGLContext.getEGL() as EGL10
            this.egl = egl
            eglDisplay = egl.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY)
            val version = IntArray(2)
            egl.eglInitialize(eglDisplay, version)
            eglConfig = chooseConfig(egl)
            eglSurface = egl.eglCreateWindowSurface(eglDisplay, eglConfig, surface, null)
            eglContext = createContext(egl, eglDisplay, eglConfig)
            if (eglSurface == null || eglSurface == EGL10.EGL_NO_SURFACE) {
                ALog.e(TAG, "error:${Integer.toHexString(egl.eglGetError())}")
                return false
            }
            if (!egl.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                ALog.e(TAG, "make current error:${Integer.toHexString(egl.eglGetError())}")
                return false
            }
            return true
        } catch (e: Throwable) {
            ALog.e(TAG, "error:$e", e)
            return false
        }
    }

    /**
     * Replaces the window surface while keeping the EGL context — and with it
     * all GL objects (programs, the OES texture MediaCodec renders into) —
     * alive. Returns true on success.
     */
    fun recreateSurface(surface: Surface): Boolean {
        val egl = egl ?: return false
        try {
            egl.eglMakeCurrent(
                eglDisplay, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT
            )
            if (eglSurface != EGL10.EGL_NO_SURFACE) {
                egl.eglDestroySurface(eglDisplay, eglSurface)
            }
            eglSurface = egl.eglCreateWindowSurface(eglDisplay, eglConfig, surface, null)
            if (eglSurface == null || eglSurface == EGL10.EGL_NO_SURFACE) {
                ALog.e(TAG, "recreate error:${Integer.toHexString(egl.eglGetError())}")
                return false
            }
            if (!egl.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                ALog.e(TAG, "recreate make current error:${Integer.toHexString(egl.eglGetError())}")
                return false
            }
            return true
        } catch (e: Throwable) {
            ALog.e(TAG, "error:$e", e)
            return false
        }
    }

    fun surfaceWidth(): Int = querySurface(EGL10.EGL_WIDTH)

    fun surfaceHeight(): Int = querySurface(EGL10.EGL_HEIGHT)

    private fun querySurface(attribute: Int): Int {
        val value = IntArray(1)
        val ok = egl?.eglQuerySurface(eglDisplay, eglSurface, attribute, value) == true
        return if (ok) value[0] else 0
    }

    private fun chooseConfig(egl: EGL10): EGLConfig? {
        val configsCount = IntArray(1)
        val configs = arrayOfNulls<EGLConfig>(1)
        val attributes = intArrayOf(
            EGL10.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL10.EGL_RED_SIZE, 8,
            EGL10.EGL_GREEN_SIZE, 8,
            EGL10.EGL_BLUE_SIZE, 8,
            EGL10.EGL_ALPHA_SIZE, 8,
            EGL10.EGL_DEPTH_SIZE, 0,
            EGL10.EGL_STENCIL_SIZE, 0,
            EGL10.EGL_NONE
        )
        if (egl.eglChooseConfig(eglDisplay, attributes, configs, 1, configsCount)) {
            return configs[0]
        }
        return null
    }

    private fun createContext(
        egl: EGL10?,
        eglDisplay: EGLDisplay?,
        eglConfig: EGLConfig?,
    ): EGLContext? {
        val attrs = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL10.EGL_NONE
        )
        return egl?.eglCreateContext(eglDisplay, eglConfig, EGL10.EGL_NO_CONTEXT, attrs)
    }

    fun swapBuffers() {
        if (eglDisplay == null || eglSurface == null) return
        egl?.eglSwapBuffers(eglDisplay, eglSurface)
    }

    fun release() {
        egl?.apply {
            eglMakeCurrent(eglDisplay, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT)
            eglDestroySurface(eglDisplay, eglSurface)
            eglDestroyContext(eglDisplay, eglContext)
            eglTerminate(eglDisplay)
        }
        egl = null
        eglDisplay = EGL10.EGL_NO_DISPLAY
        eglSurface = EGL10.EGL_NO_SURFACE
        eglContext = EGL10.EGL_NO_CONTEXT
        eglConfig = null
    }
}
