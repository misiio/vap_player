import Flutter
import UIKit
import XCTest
@testable import vap_player_ios

class RunnerTests: XCTestCase {

  func testOldVersionCompatibilityError() {
    let error = VapPlayerInstance.oldVersionCompatibilityError(
      hasVapcBox: false,
      enableOldVersion: false)

    XCTAssertEqual(error?.errorType, 10005)
    XCTAssertEqual(error?.errorMsg, "0x5 parse config fail")
  }

  func testOldVersionCompatibilityAllowsExplicitlyEnabledFiles() {
    XCTAssertNil(
      VapPlayerInstance.oldVersionCompatibilityError(
        hasVapcBox: false,
        enableOldVersion: true))
  }

  func testOldVersionCompatibilityAllowsFilesWithVapcBox() {
    XCTAssertNil(
      VapPlayerInstance.oldVersionCompatibilityError(
        hasVapcBox: true,
        enableOldVersion: false))
  }

}
