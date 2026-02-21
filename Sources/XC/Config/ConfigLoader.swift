import Foundation
import Yams

enum ConfigLoader {
    struct LoadedConfig: Sendable {
        let project: ProjectConfig
        let global: GlobalConfig?
    }

    static func load(from directory: String? = nil) throws -> LoadedConfig {
        let projectConfig = try loadProjectConfig(from: directory)
        try validate(projectConfig)
        let globalConfig = try loadGlobalConfig()
        return LoadedConfig(project: projectConfig, global: globalConfig)
    }

    static func validate(_ config: ProjectConfig) throws {
        if config.project != nil && config.workspace != nil {
            throw XCError.invalidConfig("Both 'project' and 'workspace' are set. Use one or the other.")
        }
        if config.commands == nil || config.commands!.isEmpty {
            throw XCError.invalidConfig("No commands defined. Add a 'commands' section to xc.yaml.")
        }
    }

    static func loadProjectConfig(from directory: String? = nil) throws -> ProjectConfig {
        let dir = directory ?? FileManager.default.currentDirectoryPath
        let path = dir + "/xc.yaml"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCError.configNotFound
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = String(data: data, encoding: .utf8) ?? ""
        return try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
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
