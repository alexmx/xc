import Foundation

enum XCError: LocalizedError {
    case configNotFound
    case unknownCommand(String)
    case unknownVariant(String, String)
    case buildFailed(Int32)
    case hookFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            "No xc.yaml found in the current directory."
        case .unknownCommand(let name):
            "Unknown command '\(name)'. Check the 'commands' section in xc.yaml."
        case .unknownVariant(let command, let variant):
            "Unknown variant '\(variant)' for command '\(command)'. Check xc.yaml."
        case .buildFailed(let code):
            "xcodebuild exited with code \(code)."
        case .hookFailed(let label, let code):
            "Hook '\(label)' failed with exit code \(code)."
        }
    }
}
