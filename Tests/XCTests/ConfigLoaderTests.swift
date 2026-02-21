import Foundation
@testable import xc
import Testing
import Yams

@Suite("ConfigLoader Tests")
struct ConfigLoaderTests {
    // MARK: - YAML Parsing

    @Test("parse full config YAML")
    func parseFullConfig() throws {
        let yaml = """
            project: MyApp.xcodeproj

            destinations:
              sim: "platform:iOS Simulator,name:iPhone 16"
              device: "platform:iOS,name:My iPhone"

            defaults:
              scheme: MyApp
              configuration: Debug
              destination: sim

            commands:
              build:
                hooks:
                  pre: "swiftlint lint"
                  post: "echo done"
                variants:
                  release:
                    configuration: Release
                    destination: device

              test:
                scheme: MyAppTests
                extra-args:
                  - "-enableCodeCoverage"
                  - "YES"

              clean: {}

              archive:
                configuration: Release
                archive-path: "./build/MyApp.xcarchive"
            """

        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)

        #expect(config.project == "MyApp.xcodeproj")
        #expect(config.workspace == nil)
        #expect(config.destinations?["sim"] == "platform:iOS Simulator,name:iPhone 16")
        #expect(config.destinations?["device"] == "platform:iOS,name:My iPhone")
        #expect(config.defaults?.scheme == "MyApp")
        #expect(config.defaults?.configuration == "Debug")
        #expect(config.defaults?.destination == "sim")

        let buildCmd = try #require(config.commands?["build"])
        #expect(buildCmd.hooks?.pre == "swiftlint lint")
        #expect(buildCmd.hooks?.post == "echo done")
        #expect(buildCmd.variants?["release"]?.configuration == "Release")
        #expect(buildCmd.variants?["release"]?.destination == "device")

        let testCmd = try #require(config.commands?["test"])
        #expect(testCmd.scheme == "MyAppTests")
        #expect(testCmd.extraArgs == ["-enableCodeCoverage", "YES"])

        #expect(config.commands?["clean"] != nil)

        let archiveCmd = try #require(config.commands?["archive"])
        #expect(archiveCmd.configuration == "Release")
        #expect(archiveCmd.archivePath == "./build/MyApp.xcarchive")
    }

    @Test("parse minimal config with only commands")
    func parseMinimalConfig() throws {
        let yaml = """
            commands:
              build:
                scheme: MyApp
            """

        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)

        #expect(config.project == nil)
        #expect(config.workspace == nil)
        #expect(config.destinations == nil)
        #expect(config.defaults == nil)
        #expect(config.commands?["build"]?.scheme == "MyApp")
    }

    @Test("parse workspace config")
    func parseWorkspaceConfig() throws {
        let yaml = """
            workspace: MyApp.xcworkspace
            commands:
              build: {}
            """

        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)

        #expect(config.workspace == "MyApp.xcworkspace")
        #expect(config.project == nil)
    }

    @Test("parse global config")
    func parseGlobalConfig() throws {
        let yaml = """
            defaults:
              destination: "platform:iOS Simulator,name:iPhone 16"

            settings:
              formatter: xcbeautify
              verbose: false
            """

        let config = try YAMLDecoder().decode(GlobalConfig.self, from: yaml)

        #expect(config.defaults?.destination == "platform:iOS Simulator,name:iPhone 16")
        #expect(config.settings?.formatter == "xcbeautify")
        #expect(config.settings?.verbose == false)
    }

    @Test("parse config with multiple variants")
    func parseMultipleVariants() throws {
        let yaml = """
            commands:
              build:
                scheme: MyApp
                configuration: Debug
                variants:
                  release:
                    configuration: Release
                  staging:
                    configuration: Release
                    extra-args:
                      - "STAGING=1"
            """

        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)

        let buildCmd = try #require(config.commands?["build"])
        #expect(buildCmd.variants?.count == 2)
        #expect(buildCmd.variants?["release"]?.configuration == "Release")
        #expect(buildCmd.variants?["staging"]?.extraArgs == ["STAGING=1"])
    }

    @Test("parse config with hooks at variant level")
    func parseVariantHooks() throws {
        let yaml = """
            commands:
              build:
                hooks:
                  pre: "base-pre"
                variants:
                  release:
                    hooks:
                      pre: "release-pre"
                      post: "release-post"
            """

        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)

        let buildCmd = try #require(config.commands?["build"])
        #expect(buildCmd.hooks?.pre == "base-pre")
        #expect(buildCmd.variants?["release"]?.hooks?.pre == "release-pre")
        #expect(buildCmd.variants?["release"]?.hooks?.post == "release-post")
    }
}
