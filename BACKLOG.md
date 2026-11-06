# Backlog

- **`steps:` for chained `run:` commands.** Let a command list several steps (e.g. a
  `gate` of lint, build, test) that stop at the first failure and print how long each
  step took. Today chains are one `run:` string joined with `&&`, with no timing.
