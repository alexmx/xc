import Foundation

enum EnvExpander {
    /// Expand `${VAR}` and `${VAR:-default}` patterns in a string.
    /// Only the `${}` syntax is supported — bare `$VAR` is not expanded.
    static func expand(
        _ string: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        var result = ""
        var remaining = string[...]

        while let dollarIndex = remaining.firstIndex(of: "$") {
            // Append everything before the $
            result += remaining[remaining.startIndex..<dollarIndex]

            let afterDollar = remaining.index(after: dollarIndex)
            guard afterDollar < remaining.endIndex, remaining[afterDollar] == "{" else {
                // Not ${...}, just a literal $
                result += "$"
                remaining = remaining[afterDollar...]
                continue
            }

            let afterBrace = remaining.index(after: afterDollar)
            guard let closingBrace = remaining[afterBrace...].firstIndex(of: "}") else {
                // No closing brace — treat as literal
                result += "${"
                remaining = remaining[afterBrace...]
                continue
            }

            let content = String(remaining[afterBrace..<closingBrace])
            let (varName, defaultValue) = parseVarExpression(content)

            if let envValue = environment[varName], !envValue.isEmpty {
                result += envValue
            } else if let defaultValue {
                result += defaultValue
            }
            // If no env value and no default, expand to empty string

            remaining = remaining[remaining.index(after: closingBrace)...]
        }

        result += remaining
        return result
    }

    /// Parse "VAR" or "VAR:-default" into (name, default).
    static func parseVarExpression(_ expr: String) -> (name: String, defaultValue: String?) {
        guard let range = expr.range(of: ":-") else {
            return (expr, nil)
        }
        let name = String(expr[expr.startIndex..<range.lowerBound])
        let defaultValue = String(expr[range.upperBound...])
        return (name, defaultValue)
    }
}

// MARK: - Config expansion

extension String {
    func envExpanded(_ env: [String: String]) -> String {
        EnvExpander.expand(self, environment: env)
    }
}

extension ProjectConfig {
    func expandingEnvVars(_ env: [String: String] = ProcessInfo.processInfo.environment) -> ProjectConfig {
        ProjectConfig(
            project: project?.envExpanded(env),
            workspace: workspace?.envExpanded(env),
            destinations: destinations?.mapValues { $0.envExpanded(env) },
            defaults: defaults?.expandingEnvVars(env),
            commands: commands?.mapValues { $0.expandingEnvVars(env) },
            settings: settings,
            members: members?.mapValues { $0.envExpanded(env) }
        )
    }
}

extension CommandConfig {
    func expandingEnvVars(_ env: [String: String] = ProcessInfo.processInfo.environment) -> CommandConfig {
        CommandConfig(
            run: run?.envExpanded(env),
            scheme: scheme?.envExpanded(env),
            configuration: configuration?.envExpanded(env),
            destination: destination?.expandingEnvVars(env),
            testPlan: testPlan?.envExpanded(env),
            resultBundlePath: resultBundlePath?.envExpanded(env),
            xcconfig: xcconfig?.envExpanded(env),
            derivedDataPath: derivedDataPath?.envExpanded(env),
            archivePath: archivePath?.envExpanded(env),
            extraArgs: extraArgs?.map { $0.envExpanded(env) },
            hooks: hooks?.expandingEnvVars(env),
            variants: variants?.mapValues { $0.expandingEnvVars(env) }
        )
    }
}

extension OneOrMany {
    func expandingEnvVars(_ env: [String: String]) -> OneOrMany {
        OneOrMany(values.map { $0.envExpanded(env) })
    }
}

extension HookConfig {
    func expandingEnvVars(_ env: [String: String] = ProcessInfo.processInfo.environment) -> HookConfig {
        HookConfig(
            pre: pre?.envExpanded(env),
            post: post?.envExpanded(env)
        )
    }
}
