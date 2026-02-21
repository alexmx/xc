@testable import xc
import Testing

@Suite("XCError Tests")
struct XCErrorTests {
    @Test("configNotFound message")
    func configNotFound() {
        let error = XCError.configNotFound
        #expect(error.errorDescription?.contains("No xc.yaml found") == true)
        #expect(error.errorDescription?.contains("commands") == true)
    }

    @Test("invalidConfig message includes reason")
    func invalidConfig() {
        let error = XCError.invalidConfig("Both 'project' and 'workspace' are set.")
        #expect(error.errorDescription?.contains("Invalid xc.yaml") == true)
        #expect(error.errorDescription?.contains("Both 'project' and 'workspace' are set.") == true)
    }

    @Test("unknownCommand message lists available commands sorted")
    func unknownCommand() {
        let error = XCError.unknownCommand("deploy", available: ["test", "build", "clean"])
        let message = error.errorDescription!
        #expect(message.contains("Unknown command 'deploy'"))
        #expect(message.contains("build, clean, test"))
    }

    @Test("unknownVariant message lists available variants sorted")
    func unknownVariant() {
        let error = XCError.unknownVariant("build", "staging", available: ["release", "debug"])
        let message = error.errorDescription!
        #expect(message.contains("Unknown variant 'staging'"))
        #expect(message.contains("command 'build'"))
        #expect(message.contains("debug, release"))
    }

    @Test("unknownVariant message when no variants defined")
    func unknownVariantEmpty() {
        let error = XCError.unknownVariant("build", "release", available: [])
        let message = error.errorDescription!
        #expect(message.contains("No variants are defined"))
    }

    @Test("buildFailed message includes exit code")
    func buildFailed() {
        let error = XCError.buildFailed(65)
        #expect(error.errorDescription?.contains("65") == true)
    }

    @Test("hookFailed message includes label and exit code")
    func hookFailed() {
        let error = XCError.hookFailed("pre-build", 1)
        let message = error.errorDescription!
        #expect(message.contains("pre-build"))
        #expect(message.contains("1"))
    }
}
