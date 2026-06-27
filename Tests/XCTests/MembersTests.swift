import Foundation
import Testing
import Yams
@testable import xc

@Suite("Members Tests")
struct MembersTests {
    // MARK: - parseMemberPath

    @Test("parseMemberPath with no member")
    func parseMemberPathPlain() {
        let (member, command) = RunCommand.parseMemberPath("build")
        #expect(member == nil)
        #expect(command == "build")
    }

    @Test("parseMemberPath splits member and command")
    func parseMemberPathSplit() {
        let (member, command) = RunCommand.parseMemberPath("core/build")
        #expect(member == "core")
        #expect(command == "build")
    }

    @Test("parseMemberPath keeps variant on the command side")
    func parseMemberPathWithVariant() {
        let (member, command) = RunCommand.parseMemberPath("core/build:release")
        #expect(member == "core")
        #expect(command == "build:release")
    }

    @Test("parseMemberPath with leading slash has no member")
    func parseMemberPathLeadingSlash() {
        let (member, command) = RunCommand.parseMemberPath("/build")
        #expect(member == nil)
        #expect(command == "build")
    }

    @Test("parseMemberPath with trailing slash yields empty command")
    func parseMemberPathTrailingSlash() {
        let (member, command) = RunCommand.parseMemberPath("core/")
        #expect(member == "core")
        #expect(command == "")
    }

    // MARK: - selectMembers

    @Test("selectMembers with all returns every member")
    func selectMembersAll() throws {
        let result = try RunCommand.selectMembers(all: true, list: nil, available: ["core", "network"])
        #expect(result == ["core", "network"])
    }

    @Test("selectMembers with list filters and preserves declared order")
    func selectMembersList() throws {
        let result = try RunCommand.selectMembers(all: false, list: "network,core", available: ["core", "network", "ui"])
        #expect(result == ["core", "network"])
    }

    @Test("selectMembers trims whitespace and de-duplicates")
    func selectMembersTrimDedup() throws {
        let result = try RunCommand.selectMembers(all: false, list: " core , core ", available: ["core", "network"])
        #expect(result == ["core"])
    }

    @Test("selectMembers throws on unknown member")
    func selectMembersUnknown() {
        #expect(throws: XCError.self) {
            try RunCommand.selectMembers(all: false, list: "ghost", available: ["core", "network"])
        }
    }

    // MARK: - fanOutTargetNames

    @Test("fanOutTargetNames with --all includes the root first, then every member")
    func fanOutTargetsAll() throws {
        let result = try RunCommand.fanOutTargetNames(all: true, list: nil, available: ["core", "network"])
        #expect(result == [RunCommand.rootTarget, "core", "network"])
    }

    @Test("fanOutTargetNames with --members excludes the root")
    func fanOutTargetsMembers() throws {
        let result = try RunCommand.fanOutTargetNames(all: false, list: "network", available: ["core", "network"])
        #expect(result == ["network"])
    }

    // MARK: - ConfigLoader member helpers

    @Test("memberNames are sorted")
    func memberNamesSorted() {
        let config = ProjectConfig(commands: ["build": CommandConfig()], members: ["network": "Packages/Network", "core": "Packages/Core"])
        #expect(ConfigLoader.memberNames(config) == ["core", "network"])
    }

    @Test("memberDirectory joins relative path under projectRoot")
    func memberDirectoryRelative() {
        let config = ProjectConfig(commands: ["build": CommandConfig()], members: ["core": "Packages/Core"])
        #expect(ConfigLoader.memberDirectory("core", config: config, projectRoot: "/repo") == "/repo/Packages/Core")
    }

    @Test("memberDirectory keeps absolute paths as-is")
    func memberDirectoryAbsolute() {
        let config = ProjectConfig(commands: ["build": CommandConfig()], members: ["core": "/abs/Core"])
        #expect(ConfigLoader.memberDirectory("core", config: config, projectRoot: "/repo") == "/abs/Core")
    }

    @Test("memberDirectory returns nil for unknown member")
    func memberDirectoryUnknown() {
        let config = ProjectConfig(commands: ["build": CommandConfig()], members: ["core": "Packages/Core"])
        #expect(ConfigLoader.memberDirectory("ghost", config: config, projectRoot: "/repo") == nil)
    }

    // MARK: - Decoding

    @Test("members decode from YAML")
    func membersDecode() throws {
        let yaml = """
        members:
          core: Packages/Core
          network: Packages/Network
        commands:
          lint:
            run: "swiftlint"
        """
        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
        #expect(config.members?["core"] == "Packages/Core")
        #expect(config.members?["network"] == "Packages/Network")
    }

    @Test("member paths expand environment variables")
    func membersEnvExpand() throws {
        setenv("XC_TEST_PKG_DIR", "Vendored", 1)
        defer { unsetenv("XC_TEST_PKG_DIR") }
        let yaml = """
        members:
          core: "${XC_TEST_PKG_DIR}/Core"
        commands:
          lint:
            run: "swiftlint"
        """
        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml).expandingEnvVars()
        #expect(config.members?["core"] == "Vendored/Core")
    }

    // MARK: - loadExact

    @Test("loadExact loads a member's own xc.yaml")
    func loadExactLoadsMember() throws {
        try withTempDirectory { dir in
            let yaml = """
            commands:
              build:
                run: "swift build"
            """
            try yaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)
            let config = try ConfigLoader.loadExact(from: dir)
            #expect(config.project.commands?["build"]?.run == "swift build")
            #expect(config.projectRoot == dir)
        }
    }

    @Test("loadExact does not walk up to a parent xc.yaml")
    func loadExactNoWalkUp() throws {
        try withTempDirectory { dir in
            let parentYaml = """
            commands:
              build: {}
            """
            try parentYaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)
            let empty = dir + "/member"
            try FileManager.default.createDirectory(atPath: empty, withIntermediateDirectories: true)
            // No xc.yaml in `empty` — loadExact must fail rather than resolve the parent.
            #expect(throws: XCError.self) {
                try ConfigLoader.loadExact(from: empty)
            }
        }
    }

    private func withTempDirectory(_ body: (String) throws -> Void) throws {
        let dir = NSTemporaryDirectory() + "xc-members-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try body(dir)
    }
}
