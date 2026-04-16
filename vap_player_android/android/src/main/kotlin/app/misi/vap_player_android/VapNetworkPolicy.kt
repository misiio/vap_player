package app.misi.vap_player_android

import java.io.File
import java.io.FileInputStream
import java.net.URI
import kotlin.math.max

internal object VapNetworkFailureCode {
  const val INVALID_URL: Long = 1001L
  const val HTTP_STATUS: Long = 1002L
  const val SIZE_EXCEEDED: Long = 1003L
  const val INVALID_MEDIA: Long = 1004L
  const val NETWORK_IO: Long = 1005L
}

internal object VapNetworkPolicy {
  private const val MIN_DOWNLOAD_BYTES: Long = 10L * 1024L * 1024L
  const val MAX_REDIRECTS: Int = 3

  fun maxDownloadBytes(): Long {
    return max(MIN_DOWNLOAD_BYTES, VapNetworkCacheUtils.autoEvictionMaxBytes())
  }

  fun sanitizeUrlForError(source: String): String {
    val uri = try {
      URI(source)
    } catch (_: Exception) {
      return "<invalid-url>"
    }
    val scheme = uri.scheme?.lowercase() ?: return "<invalid-url>"
    val host = uri.host ?: return "<invalid-url>"
    val port = if (uri.port >= 0) ":${uri.port}" else ""
    val path = uri.rawPath ?: ""
    return "$scheme://$host$port$path"
  }

  fun hasIsoBmffSignature(file: File): Boolean {
    if (!file.isFile || file.length() < 12L) {
      return false
    }
    val header = ByteArray(12)
    val bytesRead = FileInputStream(file).use { input ->
      input.read(header)
    }
    if (bytesRead < 12) {
      return false
    }
    val boxType = String(header, 4, 4, Charsets.US_ASCII)
    return boxType == "ftyp"
  }
}

internal class NetworkPlaybackException(
  val errorCode: Long,
  override val message: String,
  cause: Throwable? = null,
) : Exception(message, cause)
