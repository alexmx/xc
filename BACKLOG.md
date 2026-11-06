# Backlog

- **`steps:` for chained `run:` commands.** Let a command list several steps (e.g. a
  `gate` of lint, build, test) that stop at the first failure and print how long each
  step took. Today chains are one `run:` string joined with `&&`, with no timing.
- **Hook banners print out of order when stdout is piped.** `→ Running pre-x hook...`
  shows up after the hook's own output in CI logs or `xc ... | cat`, because HookRunner
  prints without `fflush` before starting the child (fan-out already uses `announce`).
