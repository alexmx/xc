import Testing
@testable import xc

@Suite("CommandRef Tests")
struct CommandRefTests {
    @Test("parses member, name and variant", arguments: [
        ("build", nil, "build", nil),
        ("build:release", nil, "build", "release"),
        ("build:my-custom", nil, "build", "my-custom"),
        ("build:a:b", nil, "build", "a:b"),
        ("build-for-testing", nil, "build-for-testing", nil),
        ("build-for-testing:ci", nil, "build-for-testing", "ci"),
        ("core/build", "core", "build", nil),
        ("core/build:release", "core", "build", "release"),
        ("/build", nil, "build", nil)
    ] as [(String, String?, String, String?)])
    func parses(input: String, member: String?, name: String, variant: String?) throws {
        #expect(try CommandRef(parsing: input) == CommandRef(member: member, name: name, variant: variant))
    }

    @Test("rejects a reference without a command name or with an empty variant", arguments: [
        ("", "missing a command name"),
        ("core/", "missing a command name"),
        (":release", "missing a command name"),
        ("build:", "missing a variant name after ':'")
    ])
    func rejects(input: String, reason: String) {
        do {
            let ref = try CommandRef(parsing: input)
            Issue.record("parsed '\(input)' as \(ref)")
        } catch {
            #expect(error.localizedDescription == "Invalid command '\(input)': \(reason).")
        }
    }
}
