import Foundation
import Testing
@testable import xc

@Suite("XC_ROOT Tests")
struct XCRootTests {
    private func withTempDirectory(_ body: (String) throws -> Void) throws {
        let tempDir = NSTemporaryDirectory() + "xc-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        try body(tempDir)
    }

    @Test("expand reads variables from the given environment")
    func expandUsesGivenEnvironment() {
        #expect(EnvExpander.expand("${XC_ROOT}/Build", environment: ["XC_ROOT": "/root"]) == "/root/Build")
    }

    @Test("environment sets XC_ROOT over an inherited value and keeps the rest")
    func environmentOverridesInheritedValue() {
        let env = ConfigLoader.environment(root: "/project", base: ["XC_ROOT": "/stale", "PATH": "/bin"])
        #expect(env["XC_ROOT"] == "/project")
        #expect(env["PATH"] == "/bin")
    }

    @Test("absolutePath resolves relative paths against the current directory")
    func absolutePathResolvesRelative() {
        let cwd = FileManager.default.currentDirectoryPath
        #expect(ConfigLoader.absolutePath("sub/dir") == (cwd as NSString).appendingPathComponent("sub/dir"))
        #expect(ConfigLoader.absolutePath("/already/absolute") == "/already/absolute")
    }

    @Test("XC_ROOT expands to the found root when loading from a subfolder")
    func expandsToFoundRootFromSubfolder() throws {
        try withTempDirectory { dir in
            let yaml = """
            commands:
              build:
                extra-args: ["SYMROOT=${XC_ROOT}/Build"]
            """
            try yaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)
            let sub = dir + "/Sources/Deep"
            try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)

            let loaded = try ConfigLoader.load(from: sub)
            #expect(loaded.projectRoot == dir)
            #expect(loaded.project.commands?["build"]?.extraArgs == ["SYMROOT=\(dir)/Build"])
            #expect(loaded.environment["XC_ROOT"] == dir)
        }
    }

    @Test("XC_ROOT in a member is the member's own folder")
    func memberUsesOwnFolder() throws {
        try withTempDirectory { dir in
            let member = dir + "/Packages/Core"
            try FileManager.default.createDirectory(atPath: member, withIntermediateDirectories: true)
            let yaml = """
            commands:
              build:
                derived-data-path: "${XC_ROOT}/DerivedData"
            """
            try yaml.write(toFile: member + "/xc.yaml", atomically: true, encoding: .utf8)

            let loaded = try ConfigLoader.loadExact(from: member)
            #expect(loaded.project.commands?["build"]?.derivedDataPath == "\(member)/DerivedData")
        }
    }

    @Test("hooks and run scripts see XC_ROOT in their environment")
    func hookSeesEnvironment() async throws {
        let dir = NSTemporaryDirectory() + "xc-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let out = dir + "/out.txt"
        _ = try await ShellRunner.run(
            "printf '%s' \"$XC_ROOT\" > '\(out)'",
            in: dir,
            environment: ConfigLoader.environment(root: dir)
        )
        #expect(try String(contentsOfFile: out, encoding: .utf8) == dir)
    }
}
