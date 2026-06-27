import XCTest
@testable import SamplePackage

final class SamplePackageTests: XCTestCase {
    func testGreeting() {
        XCTAssertEqual(SamplePackage().greeting(), "Hello from SamplePackage")
    }
}
