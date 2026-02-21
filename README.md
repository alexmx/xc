# xc

**Stop typing xcodebuild flags. Start shipping.**

```
xc build
xc test
xc build:release
```

That's it. No more copying 200-character xcodebuild invocations from your wiki. Define your commands once in `xc.yaml`, use them forever.

```diff
- xcodebuild build \
-   -workspace App.xcworkspace \
-   -scheme App \
-   -configuration Release \
-   -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
-   -derivedDataPath ./DerivedData

+ xc build:release
```

---

### Why xc?

- **One file, all your build commands.** `xc.yaml` lives in your repo. Everyone on the team runs the same thing.
- **Variants, not flags.** `build:release`, `test:coverage`, `archive:staging` - switch configurations in two words.
- **Named destinations.** `sim`, `mac`, `device` instead of `platform=iOS Simulator,name=iPhone 17 Pro`.
- **Script commands.** Run `swiftlint`, `tuist generate`, or anything else alongside your builds.
- **Environment variables.** `${CI_SIMULATOR:-iPhone 17 Pro}` - same config, every machine.
- **Pre/post hooks.** Lint before building, notify after archiving.
- **xcbeautify built in.** Pretty output by default, `--raw` when you need it.

---

## Install

```bash
git clone https://github.com/alexmx/xc.git
cd xc
swift build -c release
cp .build/release/xc /usr/local/bin/xc
```

Requires Swift 6.2+ and macOS 15+.

**Optional:** Install [xcbeautify](https://github.com/cpisciotta/xcbeautify) for formatted output:

```bash
brew install xcbeautify
```

## Quick Start

```bash
cd your-xcode-project

xc init            # auto-detects your project, generates xc.yaml
xc build           # build with defaults
xc test            # run tests
xc build:release   # switch to release in one word
xc doctor          # verify everything is set up correctly
```

## The Config

`xc.yaml` at the root of your project:

```yaml
workspace: App.xcworkspace

destinations:
  sim: "platform=iOS Simulator,name=iPhone 17 Pro"
  mac: "platform=macOS"

defaults:
  scheme: App
  configuration: Debug
  destination: sim

commands:
  build:
    hooks:
      pre: "swiftlint lint"
    variants:
      release:
        configuration: Release

  test:
    variants:
      coverage:
        extra-args:
          - "-enableCodeCoverage"
          - "YES"

  clean: {}

  archive:
    configuration: Release
    archive-path: "./build/App.xcarchive"

  lint:
    run: "swiftlint lint --quiet"
    variants:
      fix:
        run: "swiftlint lint --fix"
```

That config gives you all of this:

```bash
xc build              # debug build
xc build:release      # release build
xc test               # run tests
xc test:coverage      # tests with code coverage
xc archive            # create archive
xc clean              # clean build
xc lint               # run swiftlint
xc lint:fix           # autofix lint issues
```

## CLI Reference

```
xc <command>[:<variant>] [options] [-- extra-xcodebuild-args...]
```

| Command | |
|---------|---|
| `xc <command>` | Run a configured command |
| `xc list` | Show available commands and variants |
| `xc init` | Generate `xc.yaml` from your project |
| `xc doctor` | Validate setup and diagnose issues |
| `xc destinations` | List available simulators and platforms |

| Option | |
|--------|---|
| `--dest <name>` | Override destination by name or raw string |
| `--raw` | Skip xcbeautify, show raw xcodebuild output |
| `-v`, `--verbose` | Print the resolved xcodebuild invocation |
| `--dry-run` | Print the command without executing it |
| `--version` | Show version |

```bash
xc test --dest mac                             # test on macOS
xc build --verbose                             # see what xcodebuild gets
xc build --dry-run                             # inspect without running
xc test --raw -- -enableAddressSanitizer YES   # raw output + extra flags
```

## Configuration Guide

### Named Destinations

Give short names to long destination strings:

```yaml
destinations:
  sim: "platform=iOS Simulator,name=iPhone 17 Pro"
  sim-ipad: "platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
  mac: "platform=macOS"

defaults:
  destination: sim
```

Test on multiple destinations at once:

```yaml
commands:
  test:
    destination:
      - sim
      - sim-ipad
```

Run `xc destinations` to see what's available on your machine.

### Variants

A variant inherits everything from its parent command and overrides only what it specifies:

```yaml
commands:
  build:
    scheme: App
    configuration: Debug
    variants:
      release:
        configuration: Release    # only this changes
      core:
        scheme: Core              # different scheme, same config
```

```bash
xc build          # scheme: App, configuration: Debug
xc build:release  # scheme: App, configuration: Release
xc build:core     # scheme: Core, configuration: Debug
```

### Script Commands

Add a `run` field to execute shell scripts instead of xcodebuild:

```yaml
commands:
  generate:
    run: "tuist generate"

  lint:
    run: "swiftlint lint --quiet"
    variants:
      fix:
        run: "swiftlint lint --fix"

  loc:
    run: "find Sources -name '*.swift' | xargs wc -l | tail -1"
```

Scripts support hooks, variants, extra-args, and `--dry-run` like any other command.

### Environment Variables

Use `${VAR}` or `${VAR:-default}` anywhere in the config:

```yaml
destinations:
  sim: "platform=iOS Simulator,name=${IOS_SIMULATOR:-iPhone 17 Pro}"

commands:
  archive:
    archive-path: "${BUILD_DIR:-./build}/App.xcarchive"
```

```bash
IOS_SIMULATOR="iPhone SE" xc test   # override from env
```

### Hooks

Run scripts before and after any command:

```yaml
commands:
  build:
    hooks:
      pre: "swiftlint lint"
      post: "say 'build complete'"
    variants:
      release:
        hooks:
          pre: "swiftlint lint --strict"
```

### Resolution Order

Settings layer from most to least specific:

1. CLI flags (`--dest`, `-- extra-args`)
2. Variant config
3. Command config
4. Project defaults (`defaults` in `xc.yaml`)
5. Global defaults (`~/.config/xc/config.yaml`)

### Global Config

Shared defaults across all your projects at `~/.config/xc/config.yaml`:

```yaml
defaults:
  destination: "platform=iOS Simulator,name=iPhone 17 Pro"

settings:
  formatter: xcbeautify
  verbose: false
```

### Config Reference

**Root fields:**

| Field | Type | Description |
|-------|------|-------------|
| `project` | string | Path to `.xcodeproj` (mutually exclusive with `workspace`) |
| `workspace` | string | Path to `.xcworkspace` |
| `destinations` | map | Named destination aliases |
| `defaults` | object | Default settings applied to all commands |
| `commands` | map | Command definitions (required) |

**Command fields:**

| Field | Type | Description |
|-------|------|-------------|
| `run` | string | Shell script (makes this a script command) |
| `scheme` | string | Xcode scheme |
| `configuration` | string | Build configuration |
| `destination` | string or list | Destination name(s) or raw string(s) |
| `xcconfig` | string | Path to `.xcconfig` file |
| `test-plan` | string | Test plan (test commands only) |
| `result-bundle-path` | string | Result bundle path (test commands only) |
| `derived-data-path` | string | Custom derived data path |
| `archive-path` | string | Archive path (archive command only) |
| `extra-args` | list | Additional xcodebuild arguments |
| `hooks` | object | `pre` and `post` shell commands |
| `variants` | map | Named variant overrides |

## Diagnostics

```
$ xc doctor
  OK    xc.yaml
  OK    Workspace    App.xcworkspace
  OK    Scheme: App
  OK    Scheme: AppTests
  OK    Dest: sim    iPhone 17 Pro
  OK    Dest: mac    macOS
  OK    xcbeautify
  OK    Global config    ~/.config/xc/config.yaml
```

```
$ xc list
archive   configuration: Release, archive-path: ./build/App.xcarchive
build
  :release   configuration: Release
clean
lint      run: swiftlint lint --quiet
  :fix       run: swiftlint lint --fix
test
  :coverage  extra-args: -enableCodeCoverage YES
```

## License

MIT
