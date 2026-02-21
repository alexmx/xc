import Foundation
@testable import xc
import Testing

@Suite("CommandResolver Tests")
struct CommandResolverTests {
    // MARK: - Test Data

    let fullConfig = ConfigLoader.LoadedConfig(
        project: ProjectConfig(
            project: "MyApp.xcodeproj",
            destinations: [
                "sim": "platform:iOS Simulator,name:iPhone 16",
                "device": "platform:iOS,name:My iPhone",
                "mac": "platform:macOS",
            ],
            defaults: CommandSettings(
                scheme: "MyApp",
                configuration: "Debug",
                destination: "sim"
            ),
            commands: [
                "build": CommandConfig(
                    hooks: HookConfig(pre: "swiftlint lint", post: "echo done"),
                    variants: [
                        "release": CommandSettings(
                            configuration: "Release",
                            destination: "device"
                        )
                    ]
                ),
                "test": CommandConfig(
                    scheme: "MyAppTests",
                    destination: "sim",
                    extraArgs: ["-enableCodeCoverage", "YES"]
                ),
                "clean": CommandConfig(),
                "archive": CommandConfig(
                    configuration: "Release",
                    archivePath: "./build/MyApp.xcarchive",
                    variants: [
                        "staging": CommandSettings(
                            extraArgs: ["STAGING=1"]
                        )
                    ]
                ),
            ]
        ),
        global: GlobalConfig(
            defaults: CommandSettings(scheme: "GlobalDefault"),
            settings: GlobalSettings(formatter: "xcbeautify")
        )
    )

    let minimalConfig = ConfigLoader.LoadedConfig(
        project: ProjectConfig(
            commands: [
                "build": CommandConfig(scheme: "Minimal"),
            ]
        ),
        global: nil
    )

    // MARK: - Basic Resolution

    @Test("resolve build with defaults")
    func resolveBuildDefaults() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation == [
            "xcodebuild", "build",
            "-project", "MyApp.xcodeproj",
            "-scheme", "MyApp",
            "-configuration", "Debug",
            "-destination", "platform:iOS Simulator,name:iPhone 16",
        ])
    }

    @Test("resolve build:release variant overrides")
    func resolveBuildRelease() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: "release",
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation == [
            "xcodebuild", "build",
            "-project", "MyApp.xcodeproj",
            "-scheme", "MyApp",
            "-configuration", "Release",
            "-destination", "platform:iOS,name:My iPhone",
        ])
    }

    @Test("resolve test with command-level overrides and extra args")
    func resolveTest() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "test",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation == [
            "xcodebuild", "test",
            "-project", "MyApp.xcodeproj",
            "-scheme", "MyAppTests",
            "-configuration", "Debug",
            "-destination", "platform:iOS Simulator,name:iPhone 16",
            "-enableCodeCoverage", "YES",
        ])
    }

    @Test("resolve clean uses only defaults")
    func resolveClean() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "clean",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation == [
            "xcodebuild", "clean",
            "-project", "MyApp.xcodeproj",
            "-scheme", "MyApp",
            "-configuration", "Debug",
            "-destination", "platform:iOS Simulator,name:iPhone 16",
        ])
    }

    // MARK: - Archive

    @Test("resolve archive includes archivePath")
    func resolveArchive() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "archive",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation.contains("-archivePath"))
        #expect(resolved.invocation.contains("./build/MyApp.xcarchive"))
    }

    @Test("archivePath only added for archive action")
    func archivePathOnlyForArchive() throws {
        // build should not include archivePath even if configured
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(archivePath: "./should-not-appear"),
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(!resolved.invocation.contains("-archivePath"))
    }

    // MARK: - Destination Resolution

    @Test("named destination is expanded")
    func namedDestination() {
        let result = CommandResolver.resolveDestination("sim", destinations: [
            "sim": "platform:iOS Simulator,name:iPhone 16",
        ])
        #expect(result == "platform:iOS Simulator,name:iPhone 16")
    }

    @Test("raw destination passes through")
    func rawDestination() {
        let result = CommandResolver.resolveDestination(
            "platform:macOS",
            destinations: ["sim": "platform:iOS Simulator,name:iPhone 16"]
        )
        #expect(result == "platform:macOS")
    }

    @Test("nil destination returns nil")
    func nilDestination() {
        let result = CommandResolver.resolveDestination(nil, destinations: ["sim": "test"])
        #expect(result == nil)
    }

    @Test("CLI dest override takes priority")
    func destOverridePriority() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: "mac",
            extraArgs: []
        )

        #expect(resolved.invocation.contains("platform:macOS"))
    }

    // MARK: - Extra Args

    @Test("passthrough extra args appended at end")
    func passthroughArgs() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: ["-enableAddressSanitizer", "YES"]
        )

        let last2 = Array(resolved.invocation.suffix(2))
        #expect(last2 == ["-enableAddressSanitizer", "YES"])
    }

    @Test("variant extra-args replace command extra-args")
    func variantExtraArgsReplace() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "archive",
            variant: "staging",
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation.contains("STAGING=1"))
        // Should NOT contain any other extra args from base (there are none in this case)
    }

    // MARK: - Hooks

    @Test("hooks resolved from command config")
    func hooksFromCommand() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.hooks?.pre == "swiftlint lint")
        #expect(resolved.hooks?.post == "echo done")
    }

    @Test("variant hooks override command hooks")
    func variantHooksOverride() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: [
                    "build": CommandConfig(
                        hooks: HookConfig(pre: "base-hook"),
                        variants: [
                            "release": CommandSettings(
                                hooks: HookConfig(pre: "variant-hook")
                            ),
                        ]
                    ),
                ]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: "release",
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.hooks?.pre == "variant-hook")
    }

    @Test("no hooks when none defined")
    func noHooks() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "clean",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.hooks == nil)
    }

    // MARK: - Error Cases

    @Test("unknown command throws")
    func unknownCommand() {
        #expect(throws: XCError.self) {
            try CommandResolver.resolve(
                commandName: "nonexistent",
                variant: nil,
                config: fullConfig,
                destOverride: nil,
                extraArgs: []
            )
        }
    }

    @Test("unknown variant throws")
    func unknownVariant() {
        #expect(throws: XCError.self) {
            try CommandResolver.resolve(
                commandName: "build",
                variant: "nonexistent",
                config: fullConfig,
                destOverride: nil,
                extraArgs: []
            )
        }
    }

    // MARK: - Workspace & SPM

    @Test("workspace used instead of project")
    func workspaceConfig() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                workspace: "MyApp.xcworkspace",
                commands: ["build": CommandConfig()]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation.contains("-workspace"))
        #expect(resolved.invocation.contains("MyApp.xcworkspace"))
        #expect(!resolved.invocation.contains("-project"))
    }

    @Test("SPM project has no project or workspace flags")
    func spmProject() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["build": CommandConfig(scheme: "MyPackage")]
            ),
            global: nil
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(!resolved.invocation.contains("-project"))
        #expect(!resolved.invocation.contains("-workspace"))
        #expect(resolved.invocation.contains("-scheme"))
    }

    // MARK: - Global Config Fallback

    @Test("global defaults used when project defaults missing")
    func globalFallback() throws {
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                commands: ["build": CommandConfig()]
            ),
            global: GlobalConfig(
                defaults: CommandSettings(scheme: "GlobalScheme", configuration: "GlobalConfig")
            )
        )

        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation.contains("GlobalScheme"))
        #expect(resolved.invocation.contains("GlobalConfig"))
    }

    @Test("formatter resolved from global settings")
    func formatterFromGlobal() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: fullConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.formatter == "xcbeautify")
    }

    // MARK: - Minimal Config

    @Test("minimal config with only command scheme")
    func minimalConfigResolve() throws {
        let resolved = try CommandResolver.resolve(
            commandName: "build",
            variant: nil,
            config: minimalConfig,
            destOverride: nil,
            extraArgs: []
        )

        #expect(resolved.invocation == [
            "xcodebuild", "build",
            "-scheme", "Minimal",
        ])
    }
}
