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

    static func load(from directory: String? = nil) throws -> LoadedConfig {
        let (projectConfig, projectRoot) = try loadProjectConfig(from: directory)
        try validate(projectConfig)
        let globalConfig = try loadGlobalConfig()
        return LoadedConfig(project: projectConfig, global: globalConfig, projectRoot: projectRoot)
    }

    static func validate(_ config: ProjectConfig) throws {
        if config.project != nil && config.workspace != nil {
            throw XCError.invalidConfig("Both 'project' and 'workspace' are set. Use one or the other.")
        }
        if config.commands == nil || config.commands!.isEmpty {
            throw XCError.invalidConfig("No commands defined. Add a 'commands' section to xc.yaml.")
        }
    }

    /// Load xc.yaml, walking up from the given directory until found.
    /// Returns the parsed config and the directory where xc.yaml was found.
    static func loadProjectConfig(from directory: String? = nil) throws -> (ProjectConfig, String) {
        let startDir = directory ?? FileManager.default.currentDirectoryPath
        guard let configDir = findConfigDirectory(from: startDir) else {
            throw XCError.configNotFound
        }
        let path = configDir + "/xc.yaml"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
        return (config.expandingEnvVars(), configDir)
    }

    /// Walk up from `directory` looking for xc.yaml. Returns the directory containing it, or nil.
    static func findConfigDirectory(from directory: String) -> String? {
        var current = directory
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: current + "/xc.yaml") {
                return current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    static func loadGlobalConfig() throws -> GlobalConfig? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".config/xc/config.yaml").path
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        return try YAMLDecoder().decode(GlobalConfig.self, from: yaml)
    }
}
