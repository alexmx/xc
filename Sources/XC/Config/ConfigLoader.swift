import Foundation
import Yams

enum ConfigLoader {
    struct LoadedConfig: Sendable {
        let project: ProjectConfig
        let global: GlobalConfig?
        let projectRoot: String

        init(project: ProjectConfig, global: GlobalConfig?, projectRoot: String = ".") {
            self.project = project
            self.global = global
            self.projectRoot = projectRoot
        }
    }

    /// Accepted project config filenames, in priority order (`xc.yaml` wins if both exist).
    static let configFileNames = ["xc.yaml", "xc.yml"]

    /// Path to the config file in `directory` (`xc.yaml` preferred over `xc.yml`), or nil if neither exists.
    static func configFilePath(in directory: String) -> String? {
        for name in configFileNames {
            let path = directory + "/" + name
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    static func load(from directory: String? = nil) throws -> LoadedConfig {
        let (projectConfig, projectRoot) = try loadProjectConfig(from: directory)
        try validate(projectConfig)
        let globalConfig = try loadGlobalConfig()
        return LoadedConfig(project: projectConfig, global: globalConfig, projectRoot: projectRoot)
    }

    /// Load the config located exactly in `directory` (no walking up). Used for nested members,
    /// so a member directory without its own config is an error rather than silently resolving
    /// to the parent config.
    static func loadExact(from directory: String) throws -> LoadedConfig {
        guard let path = configFilePath(in: directory) else {
            throw XCError.configNotFound
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        let projectConfig: ProjectConfig
        do {
            projectConfig = try YAMLDecoder().decode(ProjectConfig.self, from: yaml).expandingEnvVars()
        } catch {
            throw XCError.invalidConfig(Self.describeYAMLError(error))
        }
        try validate(projectConfig)
        let globalConfig = try loadGlobalConfig()
        return LoadedConfig(project: projectConfig, global: globalConfig, projectRoot: directory)
    }

    /// Member names declared in a config, sorted.
    static func memberNames(_ config: ProjectConfig) -> [String] {
        (config.members ?? [:]).keys.sorted()
    }

    /// Resolve a member name to its directory, joined relative to `projectRoot`.
    /// Returns nil if the name isn't a declared member.
    static func memberDirectory(_ name: String, config: ProjectConfig, projectRoot: String) -> String? {
        guard let relative = config.members?[name] else { return nil }
        if relative.hasPrefix("/") { return relative }
        return (projectRoot as NSString).appendingPathComponent(relative)
    }

    static func validate(_ config: ProjectConfig) throws {
        if config.project != nil && config.workspace != nil {
            throw XCError.invalidConfig("Both 'project' and 'workspace' are set. Use one or the other.")
        }
        if (config.commands ?? [:]).isEmpty {
            throw XCError.invalidConfig("No commands defined. Add a 'commands' section to xc.yaml.")
        }
    }

    /// Load the project config, walking up from the given directory until found.
    /// Returns the parsed config and the directory where the config was found.
    static func loadProjectConfig(from directory: String? = nil) throws -> (ProjectConfig, String) {
        let startDir = directory ?? FileManager.default.currentDirectoryPath
        guard let configDir = findConfigDirectory(from: startDir),
              let path = configFilePath(in: configDir) else {
            throw XCError.configNotFound
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        do {
            let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
            return (config.expandingEnvVars(), configDir)
        } catch {
            throw XCError.invalidConfig(Self.describeYAMLError(error))
        }
    }

    /// Walk up from `directory` looking for a config file. Returns the directory containing it, or nil.
    static func findConfigDirectory(from directory: String) -> String? {
        var current = directory
        while true {
            if configFilePath(in: current) != nil {
                return current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    /// Extract a user-friendly description from YAML parsing or decoding errors.
    static func describeYAMLError(_ error: Error) -> String {
        // Yams throws YamlError directly for syntax issues
        if let yamlError = error as? YamlError {
            return String(describing: yamlError)
        }

        // YAMLDecoder wraps YamlError in DecodingError.dataCorrupted
        if case DecodingError.dataCorrupted(let context) = error,
           let underlying = context.underlyingError as? YamlError {
            return String(describing: underlying)
        }

        // DecodingError.typeMismatch — wrong type for a key
        if case DecodingError.typeMismatch(_, let context) = error {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty
                ? context.debugDescription
                : "\(path): \(context.debugDescription)"
        }

        // DecodingError.keyNotFound
        if case DecodingError.keyNotFound(let key, let context) = error {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let location = path.isEmpty ? "" : " in \(path)"
            return "Missing required key '\(key.stringValue)'\(location)"
        }

        return error.localizedDescription
    }

    static func loadGlobalConfig() throws -> GlobalConfig? {
        let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/xc").path
        let path = ["config.yaml", "config.yml"]
            .map { configDir + "/" + $0 }
            .first { FileManager.default.fileExists(atPath: $0) }
        guard let path else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        do {
            return try YAMLDecoder().decode(GlobalConfig.self, from: yaml)
        } catch {
            throw XCError.invalidConfig("Global config: \(describeYAMLError(error))")
        }
    }
}
