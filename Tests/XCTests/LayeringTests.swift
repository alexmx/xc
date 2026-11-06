import Testing
@testable import xc

/// Every layered setting resolves variant > command > project defaults > global defaults,
/// and the command-only settings never come from defaults.
@Suite("Layering Tests")
struct LayeringTests {
    enum Layer: String, CaseIterable {
        case variant, command, project, global
    }

    private func layer(_ name: String) -> CommandConfig {
        CommandConfig(
            scheme: "scheme-\(name)",
            configuration: "config-\(name)",
            destination: OneOrMany("dest-\(name)"),
            testPlan: "plan-\(name)",
            resultBundlePath: "bundle-\(name)",
            xcconfig: "xcconfig-\(name)",
            derivedDataPath: "dd-\(name)",
            archivePath: "archive-\(name)",
            extraArgs: ["arg-\(name)"]
        )
    }

    /// Resolve `command` (with variant "v" when the variant layer is present), setting
    /// every layer from `mostSpecific` down to global.
    private func resolve(_ action: String, mostSpecific: Layer) throws -> [String] {
        let present = Layer.allCases.drop { $0 != mostSpecific }
        var command = present.contains(.command) ? layer("command") : CommandConfig()
        if present.contains(.variant) {
            command.variants = ["v": layer("variant")]
        }
        let config = ConfigLoader.LoadedConfig(
            project: ProjectConfig(
                defaults: present.contains(.project) ? layer("project") : nil,
                commands: [action: command]
            ),
            global: GlobalConfig(defaults: layer("global"))
        )
        return try CommandResolver.resolve(
            commandName: action,
            variant: present.contains(.variant) ? "v" : nil,
            config: config,
            destOverride: nil,
            extraArgs: []
        ).xcodebuild().arguments
    }

    @Test("defaultable settings come from the most specific layer", arguments: Layer.allCases)
    func defaultableSettings(mostSpecific: Layer) throws {
        let name = mostSpecific.rawValue
        let args = try resolve("test", mostSpecific: mostSpecific)
        for (flag, value) in [
            ("-scheme", "scheme"), ("-configuration", "config"), ("-destination", "dest"),
            ("-testPlan", "plan"), ("-resultBundlePath", "bundle"), ("-xcconfig", "xcconfig"),
            ("-derivedDataPath", "dd")
        ] {
            let index = try #require(args.firstIndex(of: flag), "\(flag) missing")
            #expect(args[index + 1] == "\(value)-\(name)", "\(flag)")
        }
    }

    @Test("archive-path and extra-args come only from the variant or command", arguments: Layer.allCases)
    func commandOnlySettings(mostSpecific: Layer) throws {
        let args = try resolve("archive", mostSpecific: mostSpecific)
        switch mostSpecific {
        case .variant, .command:
            let name = mostSpecific.rawValue
            #expect(args.contains("archive-\(name)"))
            #expect(args.contains("arg-\(name)"))
        case .project, .global:
            #expect(!args.contains("-archivePath"))
            #expect(!args.contains { $0.hasPrefix("arg-") })
        }
    }
}
