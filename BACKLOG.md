# Backlog

- **`steps:` for chained `run:` commands.** Let a command list several steps (e.g. a
  `gate` of lint, build, test) that stop at the first failure and print how long each
  step took. Today chains are one `run:` string joined with `&&`, with no timing.
- **Fix the lint command.** `xc lint` runs `swiftformat --lint Sources Tests`, which
  swiftformat 0.64.5 rejects (`--lint` must come after the paths). With the flag moved,
  16 of 26 files fail newer rules (mostly `swiftTestingTestCaseNames` and wrapping).
- **Hook banners print out of order when stdout is piped.** `→ Running pre-x hook...`
  shows up after the hook's own output in CI logs or `xc ... | cat`, because HookRunner
  prints without `fflush` before starting the child (fan-out already uses `announce`).
