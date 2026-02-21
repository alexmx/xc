/// A value that decodes from either a single string or an array of strings.
struct OneOrMany: Codable, Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByArrayLiteral {
    let values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    init(_ value: String) {
        self.values = [value]
    }

    init(stringLiteral value: String) {
        self.values = [value]
    }

    init(arrayLiteral elements: String...) {
        self.values = elements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = [single]
        } else {
            values = try container.decode([String].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if values.count == 1 {
            try container.encode(values[0])
        } else {
            try container.encode(values)
        }
    }
}

struct ProjectConfig: Codable, Sendable {
    var project: String?
    var workspace: String?
    var destinations: [String: String]?
    var defaults: CommandConfig?
    var commands: [String: CommandConfig]?
}

struct CommandConfig: Codable, Sendable {
    var run: String?
    var scheme: String?
    var configuration: String?
    var destination: OneOrMany?
    var testPlan: String?
    var resultBundlePath: String?
    var derivedDataPath: String?
    var archivePath: String?
    var extraArgs: [String]?
    var hooks: HookConfig?
    var variants: [String: CommandConfig]?

    enum CodingKeys: String, CodingKey {
        case run, scheme, configuration, destination
        case testPlan = "test-plan"
        case resultBundlePath = "result-bundle-path"
        case derivedDataPath = "derived-data-path"
        case archivePath = "archive-path"
        case extraArgs = "extra-args"
        case hooks, variants
    }
}

struct HookConfig: Codable, Sendable {
    var pre: String?
    var post: String?
}
