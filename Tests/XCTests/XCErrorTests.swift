import Testing
@testable import xc

@Suite("XCError Tests")
struct XCErrorTests {
    @Test("configNotFound after walking up names the start folder and its parents")
    func configNotFoundWalkingUp() {
        let error = XCError.configNotFound(directory: "/work/app", searchedParents: true)
        #expect(error.errorDescription == """
        No xc.yaml (or xc.yml) found in /work/app or any parent directory. \
        Create one with a 'commands' section to get started.
        """)
    }

    @Test("configNotFound in one folder names just that folder")
    func configNotFoundExact() {
        let error = XCError.configNotFound(directory: "/work/app/Packages/Core", searchedParents: false)
        #expect(error.errorDescription == "No xc.yaml (or xc.yml) found in /work/app/Packages/Core.")
    }

    @Test("invalidConfig message includes reason")
    func invalidConfig() {
        let error = XCError.invalidConfig("Both 'project' and 'workspace' are set.")
        #expect(error.errorDescription?.contains("Invalid xc.yaml") == true)
        #expect(error.errorDescription?.contains("Both 'project' and 'workspace' are set.") == true)
    }

    @Test("unknownCommand message lists available commands sorted")
    func unknownCommand() throws {
        let error = XCError.unknownCommand("deploy", available: ["test", "build", "clean"])
        let message = try #require(error.errorDescription)
        #expect(message.contains("Unknown command 'deploy'"))
        #expect(message.contains("build, clean, test"))
    }

    @Test("unknownVariant message lists available variants sorted")
    func unknownVariant() throws {
        let error = XCError.unknownVariant("build", "staging", available: ["release", "debug"])
        let message = try #require(error.errorDescription)
        #expect(message.contains("Unknown variant 'staging'"))
        #expect(message.contains("command 'build'"))
        #expect(message.contains("debug, release"))
    }

    @Test("unknownVariant message when no variants defined")
    func unknownVariantEmpty() throws {
        let error = XCError.unknownVariant("build", "release", available: [])
        let message = try #require(error.errorDescription)
        #expect(message.contains("No variants are defined"))
    }

    @Test("buildFailed message includes exit code")
    func buildFailed() {
        let error = XCError.buildFailed(65)
        #expect(error.errorDescription?.contains("65") == true)
    }

    @Test("hookFailed message includes label and exit code")
    func hookFailed() throws {
        let error = XCError.hookFailed("pre-build", 1)
        let message = try #require(error.errorDescription)
        #expect(message.contains("pre-build"))
        #expect(message.contains("1"))
    }

    @Test("localizedDescription is the errorDescription, so callers need no XCError cast", arguments: [
        XCError.configNotFound(directory: "/a", searchedParents: true),
        .invalidConfig("bad"),
        .unknownCommand("x", available: ["a"]),
        .unknownVariant("x", "y", available: []),
        .unknownMember("m", available: ["a"]),
        .memberFailed("m", underlying: "why"),
        .fanOutFailed(["a"]),
        .buildFailed(1),
        .hookFailed("pre", 2)
    ])
    func localizedDescriptionMatches(error: XCError) {
        #expect((error as Error).localizedDescription == error.errorDescription)
    }
}
