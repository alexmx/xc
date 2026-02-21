@testable import Core
import XCTest

final class CoreTests: XCTestCase {
    func testHello() {
        XCTAssertEqual("Hello from Core!", Greeting.hello())
    }

    func testGreet() {
        XCTAssertEqual("Hello, World!", Greeting.greet(name: "World"))
    }
}
