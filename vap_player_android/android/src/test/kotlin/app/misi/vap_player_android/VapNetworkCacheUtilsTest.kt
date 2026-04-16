package app.misi.vap_player_android

import java.io.File
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class VapNetworkCacheUtilsTest {
  @Test
  fun `supported network URL accepts http and https`() {
    assertTrue(VapNetworkCacheUtils.isSupportedNetworkUrl("http://example.com/a.mp4"))
    assertTrue(VapNetworkCacheUtils.isSupportedNetworkUrl("https://example.com/a.mp4"))
  }

  @Test
  fun `supported network URL rejects unsupported scheme and relative URL`() {
    assertFalse(VapNetworkCacheUtils.isSupportedNetworkUrl("ftp://example.com/a.mp4"))
    assertFalse(VapNetworkCacheUtils.isSupportedNetworkUrl("/local/file.mp4"))
    assertFalse(VapNetworkCacheUtils.isSupportedNetworkUrl("not a url"))
    assertFalse(VapNetworkCacheUtils.isSupportedNetworkUrl("https:///no-host.mp4"))
  }

  @Test
  fun `cache file for URL is stable and isolated by URL`() {
    val cacheRoot = File("/tmp")
    val first = VapNetworkCacheUtils.cacheFileForUrl(cacheRoot, "https://example.com/a.mp4")
    val firstAgain = VapNetworkCacheUtils.cacheFileForUrl(cacheRoot, "https://example.com/a.mp4")
    val second = VapNetworkCacheUtils.cacheFileForUrl(cacheRoot, "https://example.com/b.mp4")

    assertEquals(first.absolutePath, firstAgain.absolutePath)
    assertNotEquals(first.absolutePath, second.absolutePath)
    assertTrue(first.absolutePath.contains("vap_player/network"))
    assertTrue(first.name.endsWith(".mp4"))
  }

  @Test
  fun `network cache size sums file sizes in cache directory`() {
    val cacheRoot = createTempCacheRoot()
    createCacheFile(cacheRoot, "a.mp4", 3, 10L)
    createCacheFile(cacheRoot, "b.mp4", 5, 20L)

    assertEquals(8L, VapNetworkCacheUtils.networkCacheSizeBytes(cacheRoot))
  }

  @Test
  fun `clear network cache deletes cached files`() {
    val cacheRoot = createTempCacheRoot()
    createCacheFile(cacheRoot, "a.mp4", 3, 10L)
    createCacheFile(cacheRoot, "b.mp4", 5, 20L)

    VapNetworkCacheUtils.clearNetworkCache(cacheRoot)

    val files = VapNetworkCacheUtils.cacheDirectory(cacheRoot).listFiles()
    assertTrue(files == null || files.isEmpty())
    assertEquals(0L, VapNetworkCacheUtils.networkCacheSizeBytes(cacheRoot))
  }

  @Test
  fun `prune network cache removes oldest files first`() {
    val cacheRoot = createTempCacheRoot()
    val oldFile = createCacheFile(cacheRoot, "old.mp4", 4, 10L)
    val newFile = createCacheFile(cacheRoot, "new.mp4", 4, 20L)

    VapNetworkCacheUtils.pruneNetworkCacheToBytes(cacheRoot, maxBytes = 4L, protectedFile = null)

    assertFalse(oldFile.exists())
    assertTrue(newFile.exists())
    assertEquals(4L, VapNetworkCacheUtils.networkCacheSizeBytes(cacheRoot))
  }

  @Test
  fun `touch updates recency and touched file survives prune`() {
    val cacheRoot = createTempCacheRoot()
    val oldFile = createCacheFile(cacheRoot, "old.mp4", 4, 10L)
    val newFile = createCacheFile(cacheRoot, "new.mp4", 4, 20L)

    VapNetworkCacheUtils.touch(oldFile)
    VapNetworkCacheUtils.pruneNetworkCacheToBytes(cacheRoot, maxBytes = 4L, protectedFile = null)

    assertTrue(oldFile.exists())
    assertFalse(newFile.exists())
  }

  @Test
  fun `prune protects explicitly protected file`() {
    val cacheRoot = createTempCacheRoot()
    val protectedFile = createCacheFile(cacheRoot, "protected.mp4", 4, 10L)
    val otherFile = createCacheFile(cacheRoot, "other.mp4", 4, 20L)

    VapNetworkCacheUtils.pruneNetworkCacheToBytes(
      cacheRoot = cacheRoot,
      maxBytes = 4L,
      protectedFile = protectedFile,
    )

    assertTrue(protectedFile.exists())
    assertFalse(otherFile.exists())
  }

  @Test
  fun `prune rejects negative max bytes`() {
    val cacheRoot = createTempCacheRoot()
    assertFailsWith<IllegalArgumentException> {
      VapNetworkCacheUtils.pruneNetworkCacheToBytes(cacheRoot, maxBytes = -1L, protectedFile = null)
    }
  }

  @Test
  fun `auto-eviction max bytes can be updated`() {
    VapNetworkCacheUtils.setAutoEvictionMaxBytes(1024L)
    assertEquals(1024L, VapNetworkCacheUtils.autoEvictionMaxBytes())
  }

  @Test
  fun `auto-eviction max bytes rejects negative values`() {
    assertFailsWith<IllegalArgumentException> {
      VapNetworkCacheUtils.setAutoEvictionMaxBytes(-1L)
    }
  }

  @Test
  fun `effective max download bytes uses at least ten MiB`() {
    VapNetworkCacheUtils.setAutoEvictionMaxBytes(128 * 1024L)

    assertEquals(10L * 1024L * 1024L, VapNetworkPolicy.maxDownloadBytes())
  }

  @Test
  fun `effective max download bytes follows configured auto eviction when larger`() {
    VapNetworkCacheUtils.setAutoEvictionMaxBytes(16L * 1024L * 1024L)

    assertEquals(16L * 1024L * 1024L, VapNetworkPolicy.maxDownloadBytes())
  }

  @Test
  fun `sanitize URL removes query and fragment`() {
    val sanitized = VapNetworkPolicy.sanitizeUrlForError(
      "https://cdn.example.com/path/to/demo.mp4?token=secret#section",
    )

    assertEquals("https://cdn.example.com/path/to/demo.mp4", sanitized)
    assertFalse(sanitized.contains("?"))
    assertFalse(sanitized.contains("#"))
  }

  @Test
  fun `sanitize URL returns placeholder for invalid input`() {
    val sanitized = VapNetworkPolicy.sanitizeUrlForError("not-a-valid-url")
    assertEquals("<invalid-url>", sanitized)
  }

  @Test
  fun `mp4 signature sanity check accepts ftyp header`() {
    val cacheRoot = createTempCacheRoot()
    val file = File(cacheRoot, "valid.mp4")
    file.outputStream().use { output ->
      output.write(byteArrayOf(0x00, 0x00, 0x00, 0x18))
      output.write("ftyp".toByteArray(Charsets.US_ASCII))
      output.write(ByteArray(16) { 0x00 })
    }

    assertTrue(VapNetworkPolicy.hasIsoBmffSignature(file))
  }

  @Test
  fun `mp4 signature sanity check rejects invalid header`() {
    val cacheRoot = createTempCacheRoot()
    val file = File(cacheRoot, "invalid.mp4")
    file.outputStream().use { output ->
      output.write(byteArrayOf(0x00, 0x00, 0x00, 0x18))
      output.write("moov".toByteArray(Charsets.US_ASCII))
      output.write(ByteArray(16) { 0x00 })
    }

    assertFalse(VapNetworkPolicy.hasIsoBmffSignature(file))
  }

  private fun createTempCacheRoot(): File {
    return createTempDirectory("vap-network-cache-test").toFile()
  }

  private fun createCacheFile(cacheRoot: File, name: String, size: Int, lastModified: Long): File {
    val cacheDir = VapNetworkCacheUtils.cacheDirectory(cacheRoot)
    cacheDir.mkdirs()
    val file = File(cacheDir, name)
    file.outputStream().use { output ->
      output.write(ByteArray(size) { 1 })
    }
    file.setLastModified(lastModified)
    return file
  }
}
