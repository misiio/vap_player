package app.misi.vap_player_android

import kotlin.test.Test
import kotlin.test.assertEquals

class VapPlayerPlatformViewTextFallbackTest {
  @Test
  fun `resolveTextResourceValue returns mapped value when tag is present`() {
    val tagValues = mapOf("[textUser]" to "Alice")

    val resolved = resolveTextResourceValue(tagValues, "[textUser]")

    assertEquals("Alice", resolved)
  }

  @Test
  fun `resolveTextResourceValue returns tag when mapping is missing`() {
    val tagValues = mapOf("[textUser]" to "Alice")

    val resolved = resolveTextResourceValue(tagValues, "[textMissing]")

    assertEquals("[textMissing]", resolved)
  }
}
