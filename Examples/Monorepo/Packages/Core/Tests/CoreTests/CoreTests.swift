import XCTest
@testable import Core

final class CoreTests: XCTestCase {
    func testVersion() { XCTAssertEqual(Core().version(), "1.0.0") }
}
