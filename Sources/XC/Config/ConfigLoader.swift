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

        /// The environment commands run with: the inherited one plus `XC_ROOT`.
        var environment: [String: String] {
            ConfigLoader.environment(root: projectRoot)
        }
    }

    /// The inherited environment with `XC_ROOT` set to `root`. The built-in value wins
    /// over an inherited `XC_ROOT`, so a stale export can't point a build elsewhere.
    static func environment(
        root: String,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        base.merging(["XC_ROOT": root]) { _, builtin in builtin }
    }

    /// Resolve `path` against the current directory. `XC_ROOT` must be absolute, since
    /// xcodebuild and SwiftPM resolve relative paths against different folders.
    static func absolutePath(_ path: String) -> String {
        guard !path.hasPrefix("/") else { return path }
        // URL.standardized only collapses "." and "..", unlike standardizingPath,
        // which also drops a leading /private and so changes the reported root.
        return URL(fileURLWithPath: path).standardized.path
    }

    /// Accepted project config filenames, in priority order (`xc.yaml` wins if both exist).
    static let configFileNames = ["xc.yaml", "xc.yml"]

    /// Path to the config file in `directory` (`xc.yaml` preferred over `xc.yml`), or nil if neither exists.
    static func configFilePath(in directory: String) -> String? {
        for name in configFileNames {
            let path = directory + "/" + name
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func load(from directory: String? = nil) throws -> LoadedConfig {
        let (config, root) = try loadProjectConfig(from: directory)
        return try finishLoading(config, root: root)
    }

    /// Load the config located exactly in `directory` (no walking up). Used for nested members,
    /// so a member directory without its own config is an error rather than silently resolving
    /// to the parent config.
    static func loadExact(from directory: String) throws -> LoadedConfig {
        let directory = absolutePath(directory)
        return try finishLoading(decodeProject(inDirectory: directory), root: directory)
    }

    /// Validate the project config and pair it with the global config.
    private static func finishLoading(_ config: ProjectConfig, root: String) throws -> LoadedConfig {
        try validate(config)
        let globalConfig = try loadGlobalConfig(environment: environment(root: root))
        return LoadedConfig(project: config, global: globalConfig, projectRoot: root)
    }

    /// Read and decode the config file in `directory`, expanding `${VAR}` with `XC_ROOT`
    /// set to `directory`. Not validated.
    static func decodeProject(inDirectory directory: String) throws -> ProjectConfig {
        guard let path = configFilePath(in: directory) else {
            throw XCError.configNotFound(directory: directory, searchedParents: false)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        do {
            return try decode(ProjectConfig.self, yaml: yaml, environment: environment(root: directory))
        } catch {
            throw XCError.invalidConfig(describeYAMLError(error))
        }
    }

    /// A nested project declared under `members`.
    struct Member: Equatable {
        let name: String
        /// The path as written in xc.yaml.
        let path: String
        /// `path` resolved against the declaring project's root.
        let directory: String
    }

    /// The members `config` declares, sorted by name. Relative paths are joined under `root`.
    static func members(of config: ProjectConfig, root: String) -> [Member] {
        (config.members ?? [:]).sorted { $0.key < $1.key }.map { name, path in
            let directory = path.hasPrefix("/") ? path : (root as NSString).appendingPathComponent(path)
            return Member(name: name, path: path, directory: directory)
        }
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
    /// Returns the parsed (not validated) config and the directory where it was found.
    static func loadProjectConfig(from directory: String? = nil) throws -> (config: ProjectConfig, root: String) {
        let startDir = absolutePath(directory ?? FileManager.default.currentDirectoryPath)
        guard let root = findConfigDirectory(from: startDir) else {
            throw XCError.configNotFound(directory: startDir, searchedParents: true)
        }
        return try (decodeProject(inDirectory: root), root)
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

    /// Decode `yaml` as `type`, expanding `${VAR}` in its values (not keys) first.
    /// Parses the way `YAMLDecoder.decode(_:from: String)` does, so merge keys keep working.
    static func decode<T: Decodable>(_ type: T.Type, yaml: String, environment: [String: String]) throws -> T {
        let parser = try Parser(yaml: yaml, resolver: .basic.appending(.merge))
        // The parser owns the anchors that nodes refer to weakly; keep it alive while decoding.
        return try withExtendedLifetime(parser) {
            let node = try parser.singleRoot() ?? ""
            return try YAMLDecoder().decode(type, from: node.expandingEnvVars(environment))
        }
    }

    /// `environment` feeds `${VAR}` expansion; pass the project's, so `${XC_ROOT}` is its root.
    static func loadGlobalConfig(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> GlobalConfig? {
        guard let path = globalConfigPath() else { return nil }
        return try loadGlobalConfig(at: path, environment: environment)
    }

    static func loadGlobalConfig(
        at path: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> GlobalConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        do {
            return try decode(GlobalConfig.self, yaml: yaml, environment: environment)
        } catch {
            throw XCError.invalidConfig("Global config: \(describeYAMLError(error))")
        }
    }

    /// `~/.config/xc/config.yaml`, else `config.yml`, whichever exists first.
    static func globalConfigPath(home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String? {
        ["config.yaml", "config.yml"]
            .map { home + "/.config/xc/" + $0 }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
