import XCTest

@testable import Core

final class AppTests: XCTestCase {
    func testGreeting() {
        XCTAssertEqual("Hello from Core (macOS)!", Greeting.hello())
    }
}
