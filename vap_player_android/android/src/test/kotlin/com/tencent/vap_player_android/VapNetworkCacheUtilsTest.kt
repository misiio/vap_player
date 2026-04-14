package com.tencent.vap_player_android

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
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
}
