import Foundation
import Testing
@testable import xc

@Suite("Capture Tests")
struct CaptureTests {
    @Test("output larger than a pipe buffer is captured in full", .timeLimit(.minutes(1)))
    func largeOutputDoesNotHang() async {
        let data = await Capture.output("/bin/sh", ["-c", "head -c 200000 /dev/zero"])
        #expect(data?.count == 200_000)
    }

    @Test("a command that can't launch returns nil")
    func launchFailureReturnsNil() async {
        #expect(await Capture.output("/nonexistent/tool", []) == nil)
    }

    @Test("a non-zero exit returns nil")
    func failureReturnsNil() async {
        #expect(await Capture.output("/bin/sh", ["-c", "echo partial; exit 3"]) == nil)
    }

    @Test("the working directory is honored")
    func workingDirectory() async {
        let data = await Capture.output("/bin/pwd", [], in: "/usr")
        #expect(data.flatMap { String(data: $0, encoding: .utf8) } == "/usr\n")
    }

    @Test("simctl JSON keeps available devices by runtime, in listed order")
    func parseSimulators() {
        let json = """
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"name": "iPhone 17 Pro", "isAvailable": true, "udid": "A"},
            {"name": "iPhone Old", "isAvailable": false},
            {"name": "iPhone Air", "isAvailable": true}
          ],
          "com.apple.CoreSimulator.SimRuntime.tvOS-26-0": [
            {"name": "Apple TV", "isAvailable": false}
          ]
        }}
        """
        let runtimes = Simulators.parse(Data(json.utf8))
        #expect(runtimes == ["com.apple.CoreSimulator.SimRuntime.iOS-26-0": ["iPhone 17 Pro", "iPhone Air"]])
    }

    @Test("malformed simctl JSON parses to no simulators")
    func parseSimulatorsMalformed() {
        #expect(Simulators.parse(Data("not json".utf8)).isEmpty)
    }

    @Test("xcodebuild -list JSON yields project or workspace schemes")
    func parseSchemes() {
        let project = #"{"project": {"name": "App", "schemes": ["App", "Core"]}}"#
        let workspace = #"{"workspace": {"name": "W", "schemes": ["W"]}}"#
        #expect(Schemes.parse(Data(project.utf8)) == ["App", "Core"])
        #expect(Schemes.parse(Data(workspace.utf8)) == ["W"])
        #expect(Schemes.parse(Data(#"{"project": {"name": "App"}}"#.utf8)) == nil)
    }
}
