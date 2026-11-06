# Backlog

- **`steps:` for chained `run:` commands.** Let a command list several steps (e.g. a
  `gate` of lint, build, test) that stop at the first failure and print how long each
  step took. Today chains are one `run:` string joined with `&&`, with no timing.
- **`xc doctor` exits 0 when checks fail.** It prints "Some checks failed" but returns
  success, so it can't gate CI. Exit non-zero on any FAIL (WARN stays 0).
