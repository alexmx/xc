@testable import Core
import XCTest

final class AppTests: XCTestCase {
    func testGreeting() {
        XCTAssertEqual("Hello from Core (macOS)!", Greeting.hello())
    }
}
