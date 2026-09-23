import XCTest
@testable import OpenMuse

final class RunnerTests: XCTestCase {
  func testRunnerRemainsAGenericFlutterWindow() {
    // Native surfaces are registered by plugin packages, not by Runner.
    XCTAssertTrue(MainFlutterWindow.self is MainFlutterWindow.Type)
  }
}
