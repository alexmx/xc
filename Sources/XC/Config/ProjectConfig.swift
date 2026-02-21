struct ProjectConfig: Codable, Sendable {
    var project: String?
    var workspace: String?
    var destinations: [String: String]?
    var defaults: CommandSettings?
    var commands: [String: CommandConfig]?
}

struct CommandConfig: Codable, Sendable {
    var scheme: String?
    var configuration: String?
    var destination: String?
    var archivePath: String?
    var extraArgs: [String]?
    var hooks: HookConfig?
    var variants: [String: CommandSettings]?

    enum CodingKeys: String, CodingKey {
        case scheme, configuration, destination
        case archivePath = "archive-path"
        case extraArgs = "extra-args"
        case hooks, variants
    }
}

struct CommandSettings: Codable, Sendable {
    var scheme: String?
    var configuration: String?
    var destination: String?
    var archivePath: String?
    var extraArgs: [String]?
    var hooks: HookConfig?

    enum CodingKeys: String, CodingKey {
        case scheme, configuration, destination
        case archivePath = "archive-path"
        case extraArgs = "extra-args"
        case hooks
    }
}

struct HookConfig: Codable, Sendable {
    var pre: String?
    var post: String?
}
