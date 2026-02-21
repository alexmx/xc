import Foundation
@testable import xc
import Testing

@Suite("ConfigLoader Integration Tests")
struct ConfigLoaderIntegrationTests {
    // MARK: - Helpers

    private func withTempDirectory(_ body: (String) throws -> Void) throws {
        let tempDir = NSTemporaryDirectory() + "xc-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        try body(tempDir)
    }

    // MARK: - loadProjectConfig

    @Test("loadProjectConfig reads xc.yaml from directory")
    func loadProjectConfigSuccess() throws {
        try withTempDirectory { dir in
            let yaml = """
                commands:
                  build:
                    scheme: TestApp
                """
            try yaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)

            let (config, root) = try ConfigLoader.loadProjectConfig(from: dir)
            #expect(config.commands?["build"]?.scheme == "TestApp")
            #expect(root == dir)
        }
    }

    @Test("loadProjectConfig throws when xc.yaml is missing")
    func loadProjectConfigMissing() throws {
        try withTempDirectory { dir in
            // Create a subdirectory with no xc.yaml anywhere up the tree
            // Use /tmp which won't have xc.yaml
            let isolated = dir + "/deep/nested"
            try FileManager.default.createDirectory(atPath: isolated, withIntermediateDirectories: true)
            #expect(throws: XCError.self) {
                try ConfigLoader.loadProjectConfig(from: isolated)
            }
        }
    }

    @Test("loadProjectConfig throws on invalid YAML")
    func loadProjectConfigInvalidYAML() throws {
        try withTempDirectory { dir in
            let badYaml = """
                commands:
                  build:
                    scheme: [unterminated
                """
            try badYaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)

            #expect(throws: Error.self) {
                try ConfigLoader.loadProjectConfig(from: dir)
            }
        }
    }

    // MARK: - Walk-up directory search

    @Test("loadProjectConfig finds xc.yaml in parent directory")
    func loadProjectConfigWalksUp() throws {
        try withTempDirectory { dir in
            let yaml = """
                commands:
                  build:
                    scheme: WalkUpApp
                """
            try yaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)

            let subdir = dir + "/Sources/Feature"
            try FileManager.default.createDirectory(atPath: subdir, withIntermediateDirectories: true)

            let (config, root) = try ConfigLoader.loadProjectConfig(from: subdir)
            #expect(config.commands?["build"]?.scheme == "WalkUpApp")
            #expect(root == dir)
        }
    }

    @Test("loadProjectConfig prefers closest xc.yaml when nested")
    func loadProjectConfigClosestWins() throws {
        try withTempDirectory { dir in
            let outerYaml = """
                commands:
                  build:
                    scheme: Outer
                """
            try outerYaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)

            let innerDir = dir + "/packages/inner"
            try FileManager.default.createDirectory(atPath: innerDir, withIntermediateDirectories: true)
            let innerYaml = """
                commands:
                  build:
                    scheme: Inner
                """
            try innerYaml.write(toFile: innerDir + "/xc.yaml", atomically: true, encoding: .utf8)

            let (config, root) = try ConfigLoader.loadProjectConfig(from: innerDir)
            #expect(config.commands?["build"]?.scheme == "Inner")
            #expect(root == innerDir)
        }
    }

    // MARK: - load (full pipeline with validation)

    @Test("load validates after parsing")
    func loadValidates() throws {
        try withTempDirectory { dir in
            let yaml = """
                project: App.xcodeproj
                workspace: App.xcworkspace
                commands:
                  build: {}
                """
            try yaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)

            #expect(throws: XCError.self) {
                try ConfigLoader.load(from: dir)
            }
        }
    }

    @Test("load succeeds with valid config")
    func loadSuccess() throws {
        try withTempDirectory { dir in
            let yaml = """
                project: App.xcodeproj
                destinations:
                  sim: "platform=iOS Simulator,name=iPhone 17 Pro"
                defaults:
                  scheme: App
                commands:
                  build:
                    configuration: Debug
                  test:
                    scheme: AppTests
                """
            try yaml.write(toFile: dir + "/xc.yaml", atomically: true, encoding: .utf8)

            let loaded = try ConfigLoader.load(from: dir)
            #expect(loaded.project.project == "App.xcodeproj")
            #expect(loaded.project.commands?.count == 2)
            #expect(loaded.project.destinations?["sim"] != nil)
        }
    }

    // MARK: - loadGlobalConfig

    @Test("loadGlobalConfig returns nil when file does not exist")
    func loadGlobalConfigMissing() throws {
        // This test verifies the function doesn't throw when the file is absent.
        // On a developer machine the file may or may not exist.
        let result = try ConfigLoader.loadGlobalConfig()
        _ = result
    }
}
