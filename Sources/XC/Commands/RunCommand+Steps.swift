import Foundation

/// Running a `steps:` command: each step runs as `xc <step>` would, in order, fail-fast
/// unless `--continue`, followed by a summary of each step's result and time.
extension RunCommand {
    private enum StepResult {
        case passed(Duration)
        case failed(Duration, String)
        case notRun
    }

    func runSteps(_ steps: [CommandRef], config: ConfigLoader.LoadedConfig) async throws {
        var results: [(step: String, result: StepResult)] = []
        var stopped = false

        for step in steps {
            guard !stopped else {
                results.append((step.text, .notRun))
                continue
            }
            Self.announce("==> \(step.text)")
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let stepConfig = try step.member.map { try loadMember($0, rootConfig: config) } ?? config
                try await execute(step, config: stepConfig, extraArgs: [], asStep: true)
                results.append((step.text, .passed(clock.now - start)))
            } catch {
                results.append((step.text, .failed(clock.now - start, error.localizedDescription)))
                stopped = !continueOnFailure
            }
        }

        guard !dryRun else { return }
        print()
        Self.printSummary(results)

        let failed = results.compactMap { step, result in
            if case .failed = result {
                step
            } else {
                nil
            }
        }
        if !failed.isEmpty {
            throw XCError.stepsFailed(failed)
        }
    }

    private static func printSummary(_ results: [(step: String, result: StepResult)]) {
        let width = results.map(\.step.count).max() ?? 0
        for (step, result) in results {
            let name = step.padding(toLength: width, withPad: " ", startingAt: 0)
            switch result {
            case .passed(let time): print("✓ \(name)  \(seconds(time))")
            case .failed(let time, let message): print("✗ \(name)  \(seconds(time))  \(message)")
            case .notRun: print("- \(name)  not run")
            }
        }
        fflush(stdout)
    }

    private static func seconds(_ duration: Duration) -> String {
        let (whole, fraction) = duration.components
        return String(format: "%6.1fs", Double(whole) + Double(fraction) / 1e18)
    }

    // MARK: - Checking the chain up front

    /// One command in a chain: `key` identifies it across configs, `label` is how it was written.
    private struct Link {
        let key: String
        let label: String

        init(_ ref: CommandRef, in config: ConfigLoader.LoadedConfig) {
            self.key = "\(config.projectRoot)|\(ref.name):\(ref.variant ?? "")"
            self.label = ref.text
        }
    }

    /// Resolve every step, recursively, so an unknown step, a broken member or a loop is
    /// reported before the first step runs.
    func checkSteps(of ref: CommandRef, config: ConfigLoader.LoadedConfig) throws {
        try checkSteps(of: ref, config: config, chain: [Link(ref, in: config)])
    }

    private func checkSteps(of ref: CommandRef, config: ConfigLoader.LoadedConfig, chain: [Link]) throws {
        let resolved = try CommandResolver.resolve(
            commandName: ref.name,
            variant: ref.variant,
            config: config,
            destOverride: dest,
            extraArgs: []
        )
        guard case .steps(let steps) = resolved.action else { return }

        for step in steps {
            let stepConfig: ConfigLoader.LoadedConfig
            do {
                stepConfig = try step.member.map { try loadMember($0, rootConfig: config) } ?? config
                _ = try CommandResolver.resolve(
                    commandName: step.name,
                    variant: step.variant,
                    config: stepConfig,
                    destOverride: dest,
                    extraArgs: []
                )
            } catch {
                throw XCError.badStep(command: ref.text, step: step.text, underlying: error.localizedDescription)
            }
            let link = Link(step, in: stepConfig)
            if chain.contains(where: { $0.key == link.key }) {
                throw XCError.stepsLoop((chain + [link]).map(\.label))
            }
            try checkSteps(of: step, config: stepConfig, chain: chain + [link])
        }
    }
}
