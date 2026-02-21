import Foundation

enum XCError: LocalizedError {
    case configNotFound
    case invalidConfig(String)
    case unknownCommand(String, available: [String])
    case unknownVariant(String, String, available: [String])
    case buildFailed(Int32)
    case hookFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            "No xc.yaml found in the current directory. Create one with a 'commands' section to get started."
        case .invalidConfig(let reason):
            "Invalid xc.yaml: \(reason)"
        case .unknownCommand(let name, let available):
            "Unknown command '\(name)'. Available commands: \(available.sorted().joined(separator: ", "))."
        case .unknownVariant(let command, let variant, let available):
            available.isEmpty
                ? "Unknown variant '\(variant)' for command '\(command)'. No variants are defined."
                : "Unknown variant '\(variant)' for command '\(command)'. Available variants: \(available.sorted().joined(separator: ", "))."
        case .buildFailed(let code):
            "xcodebuild exited with code \(code)."
        case .hookFailed(let label, let code):
            "Hook '\(label)' failed with exit code \(code)."
        }
    }
}
