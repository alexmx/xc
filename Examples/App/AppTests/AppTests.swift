import XCTest

@testable import SampleApp

final class AppTests: XCTestCase {
    func testHello() {
        let sut = AppDelegate()
        XCTAssertEqual("AppDelegate.hello()", sut.hello())
    }
}
