import Subprocess

extension Subprocess.Environment {
    /// Exactly `variables`, nothing else inherited (they already include the inherited ones).
    static func exactly(_ variables: [String: String]) -> Self {
        .custom(Dictionary(uniqueKeysWithValues: variables.compactMap { key, value in
            Key(rawValue: key).map { ($0, value) }
        }))
    }
}

extension TerminationStatus {
    /// nil on success; otherwise the exit code, or the signal number for a killed process
    /// (what Foundation's `Process.terminationStatus` reported).
    var failureCode: Int32? {
        switch self {
        case .exited(0): nil
        case .exited(let code): code
        case .signaled(let signal): signal
        }
    }
}
