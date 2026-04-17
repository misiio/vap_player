import XCTest

@testable import vap_player_ios

class RunnerTests: XCTestCase {
  func testMaxDownloadBytesUsesTenMiBFloor() {
    XCTAssertEqual(
      VapNetworkPolicy.maxDownloadBytes(autoEvictionMaxBytes: 64 * 1024),
      10 * 1024 * 1024
    )
  }

  func testSanitizeURLRemovesQueryAndFragment() {
    let sanitized = VapNetworkPolicy.sanitizeURLString(
      "https://cdn.example.com/path/demo.mp4?token=secret#frag"
    )
    XCTAssertEqual(sanitized, "https://cdn.example.com/path/demo.mp4")
    XCTAssertFalse(sanitized.contains("?"))
    XCTAssertFalse(sanitized.contains("#"))
  }

  func testIsoBmffSignatureCheck() throws {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    var bytes = Data([0x00, 0x00, 0x00, 0x18])
    bytes.append(Data("ftyp".utf8))
    bytes.append(Data(repeating: 0x00, count: 16))
    try bytes.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    XCTAssertTrue(VapNetworkPolicy.hasIsoBmffSignature(fileURL: tempURL))
  }

  func testIsoBmffSignatureRejectsInvalidHeader() throws {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    var bytes = Data([0x00, 0x00, 0x00, 0x18])
    bytes.append(Data("moov".utf8))
    bytes.append(Data(repeating: 0x00, count: 16))
    try bytes.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    XCTAssertFalse(VapNetworkPolicy.hasIsoBmffSignature(fileURL: tempURL))
  }

  func testFallbackResourceIdUsesTagWhenAvailable() {
    XCTAssertEqual(VapPlayerPlatformView.fallbackResourceId(for: "[imgAvatar]"), "[imgAvatar]")
  }

  func testFallbackResourceIdReturnsEmptyWhenTagMissing() {
    XCTAssertEqual(VapPlayerPlatformView.fallbackResourceId(for: nil), "")
  }

  func testResolveTextValueUsesMappedValueOrTagFallback() {
    let tagValues = ["[textUser]": "Alice"]
    XCTAssertEqual(
      VapPlayerPlatformView.resolveTextValue(for: "[textUser]", values: tagValues),
      "Alice"
    )
    XCTAssertEqual(
      VapPlayerPlatformView.resolveTextValue(for: "[textMissing]", values: tagValues),
      "[textMissing]"
    )
  }
}
