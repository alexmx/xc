"""Smoke test for the xc CLI: runs a built xc against this repo, its examples and
temporary fixtures, checking exit codes and output. Run it with `xc smoke`, which builds
the release binary first; `xc smoke -- <group>` runs one group (cli, dogfood, package,
app, macapp, monorepo, edge, init, steps, signals).

Needs the examples' tools (tuist, swiftlint, xcbeautify), an iPhone simulator, and the
"iPad Pro 13-inch (M5)" simulator that Examples/App's test destinations name. Fixtures
and logs go to .build/smoke.

Usage: smoke.py <xc-binary> [group]"""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

XC = os.path.abspath(sys.argv[1])
ONLY = sys.argv[2] if len(sys.argv) > 2 else None
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(REPO, ".build", "smoke", "work")
LOGS = os.path.join(REPO, ".build", "smoke", "logs")
EX = os.path.join(REPO, "Examples")

# Variables the examples read; cleared so the caller's shell can't change expected results.
CLEARED = ["IOS_SIMULATOR", "DERIVED_DATA", "BUILD_DIR", "RESULT_BUNDLE_PATH", "XC_ROOT"]
BASE_ENV = {k: v for k, v in os.environ.items() if k not in CLEARED}


def available_iphone():
    """An installed iPhone simulator, preferring a Pro that isn't a Max."""
    out = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                         capture_output=True, text=True, check=True).stdout
    names = [d["name"] for devices in json.loads(out)["devices"].values()
             for d in devices if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if not names:
        sys.exit("smoke: no iPhone simulator installed")
    pro = [n for n in names if "Pro" in n and "Max" not in n]
    return sorted(pro or names)[-1]


SIM = available_iphone()
results = []


def fixture(name, files):
    root = os.path.join(WORK, name)
    shutil.rmtree(root, ignore_errors=True)
    for path, text in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(text)
    os.makedirs(root, exist_ok=True)
    return root


def case(group, name, args, cwd, code=0, has=(), lacks=(), env=None, stdin=None, timeout=900):
    if ONLY and group != ONLY:
        return
    full_env = dict(BASE_ENV, **(env or {}))
    start = time.time()
    try:
        p = subprocess.run([XC] + args, cwd=cwd, env=full_env, input=stdin, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        out, rc = p.stdout, p.returncode
    except subprocess.TimeoutExpired as e:
        out, rc = (e.stdout or "") if isinstance(e.stdout, str) else "", "timeout"
    took = time.time() - start
    problems = []
    if rc != code:
        problems.append(f"exit {rc}, expected {code}")
    problems += [f"missing {h!r}" for h in has if h not in out]
    problems += [f"unexpected {l!r}" for l in lacks if l in out]
    log = os.path.join(LOGS, f"{group}-{name}.log".replace("/", "_"))
    with open(log, "w") as f:
        f.write(f"$ (cd {cwd} && xc {' '.join(args)})\n{out}")
    results.append((group, name, not problems, took, problems, log))
    mark = "PASS" if not problems else "FAIL"
    print(f"{mark} {group:<9} {name:<44} {took:6.1f}s {'; '.join(problems)}", flush=True)


def sigint_case():
    """Ctrl-C: SIGINT to xc's process group stops xc and its child."""
    if ONLY and ONLY != "signals":
        return
    root = fixture("sigint", {"xc.yaml": 'commands:\n  nap:\n    run: "sleep 30"\n'})
    start = time.time()
    p = subprocess.Popen([XC, "nap"], cwd=root, env=BASE_ENV, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    os.killpg(p.pid, signal.SIGINT)
    try:
        rc = p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        rc = "hung"
    time.sleep(0.5)
    leftover = subprocess.run(["pgrep", "-g", str(p.pid)], capture_output=True, text=True).stdout.split()
    ok = rc == -signal.SIGINT or rc == 130
    problems = [] if ok and not leftover else [f"exit {rc}, leftover pids {leftover}"]
    results.append(("signals", "ctrl-c stops xc and child", not problems, time.time() - start, problems, ""))
    print(f"{'PASS' if not problems else 'FAIL'} signals   {'ctrl-c stops xc and child':<44} {time.time() - start:6.1f}s {'; '.join(problems)}")


os.makedirs(LOGS, exist_ok=True)
os.makedirs(WORK, exist_ok=True)
pkg, app, mac, mono = (os.path.join(EX, d) for d in ("Package", "App", "MacApp", "Monorepo"))
dd = os.path.join(WORK, "DerivedData")

# --- CLI basics -------------------------------------------------------------
case("cli", "--version", ["--version"], REPO, has=["dev"])
case("cli", "--help lists subcommands", ["--help"], REPO, has=["run", "destinations", "init", "list", "doctor"])
case("cli", "no command prints the list", [], REPO, has=["build", "members:"])
case("cli", "run --help", ["run", "--help"], REPO, has=["--dry-run", "--raw", "--members", "--continue"])
case("cli", "list", ["list"], REPO, has=["  build", "$ swift build", "package  → Examples/Package"])
case("cli", "destinations", ["destinations"], REPO, has=["Available simulators:", "platform=iOS Simulator,name=", "Other platforms:"])

# --- the repo's own xc.yaml (dogfooding) ------------------------------------
case("dogfood", "build (swift build)", ["build"], REPO, has=["Build complete"])
case("dogfood", "lint", ["lint"], REPO, has=["SwiftFormat completed", " files require formatting.", "\n0/"])
case("dogfood", "test (swift test)", ["test"], REPO, has=["passed"], lacks=["recorded an issue"])
case("dogfood", "build --all --dry-run", ["build", "--all", "--dry-run"], REPO,
     has=["==> root", "swift build", "==> package", "==> monorepo (skipped: no 'build')"])
case("dogfood", "member command dry-run", ["package/build", "--dry-run"], REPO,
     has=["xcodebuild build -scheme SamplePackage -destination platform=macOS"])
case("dogfood", "-C directory", ["-C", "Examples/Package", "swift-test", "--dry-run"], REPO, has=["swift test --parallel"])

# --- Examples/Package: xcodebuild on macOS, scripts, flags ------------------
case("package", "build (formatted)", ["build", "--", "-derivedDataPath", dd], pkg, has=["Build Succeeded"], lacks=["** BUILD SUCCEEDED **"])
case("package", "build --raw", ["build", "--raw", "--", "-derivedDataPath", dd], pkg, has=["** BUILD SUCCEEDED **"])
case("package", "build -v prints the command", ["build", "-v", "--", "-derivedDataPath", dd], pkg,
     has=["$ xcodebuild build -scheme SamplePackage -destination platform=macOS -derivedDataPath"])
case("package", "test (xcodebuild, macOS)", ["test", "--", "-derivedDataPath", dd], pkg, has=["Test Succeeded"])
case("package", "swift-build script", ["swift-build"], pkg, has=["Build complete"])
case("package", "swift-test script", ["swift-test"], pkg, has=["passed"])
case("package", "--dest named destination", ["build", "--dest", "sim", "--dry-run"], pkg, has=["name=iPhone 17 Pro"])
case("package", "${VAR:-default} from env", ["build", "--dest", "sim", "--dry-run"], pkg, env={"IOS_SIMULATOR": SIM}, has=[f"name={SIM}'"])
case("package", "variant", ["build:ios", "--dry-run"], pkg, has=["-destination 'platform=iOS Simulator,name=iPhone 17 Pro'"])
case("package", "--dest raw string", ["build", "--dest", "platform=macOS,arch=x86_64", "--dry-run"], pkg, has=["-destination platform=macOS,arch=x86_64"])
case("package", "passthrough args are quoted", ["build", "--dry-run", "--", "-quiet", "OTHER_SWIFT_FLAGS=$(inherited) -DX"], pkg,
     has=["-quiet 'OTHER_SWIFT_FLAGS=$(inherited) -DX'"])
case("package", "clean", ["clean", "--", "-derivedDataPath", dd], pkg, has=["Clean Succeeded"])
case("package", "unknown variant", ["build:nope"], pkg, code=1, has=["Unknown variant 'nope' for command 'build'. Available variants: ios."])
case("package", "unknown command", ["nope"], pkg, code=1, has=["Unknown command 'nope'."])
case("package", "doctor fails on missing simulator", ["doctor"], pkg, code=1, has=["FAIL  Dest: sim", "Scheme: SamplePackage"])
case("package", "doctor passes with env override", ["doctor"], pkg, env={"IOS_SIMULATOR": SIM}, has=[f"OK    Dest: sim\t{SIM}"], lacks=["FAIL"])

# --- Examples/App: workspace, iOS simulator, hooks, variants ----------------
ios = {"IOS_SIMULATOR": SIM, "DERIVED_DATA": os.path.join(WORK, "AppDerivedData")}
case("app", "build (pre/post hooks, iOS sim)", ["build"], app, env=ios,
     has=["→ Running pre-build hook...", "→ Running post-build hook...", "build done", "Build Succeeded"])
case("app", "build:quick disables hooks", ["build:quick"], app, env=ios, has=["Build Succeeded"], lacks=["Running pre-build hook"])
case("app", "build:ipad variant destination", ["build:ipad", "--dry-run"], app, env=ios, has=["name=iPad Pro 13-inch (M5)'"])
case("app", "test:core on two destinations", ["test:core"], app, env=ios, has=["Test Succeeded"], timeout=1800)
case("app", "test:ci dry-run", ["test:ci", "--dry-run"], app, env=ios,
     has=["-resultBundlePath ./build/tests.xcresult -enableCodeCoverage YES", f"name={SIM}'", "name=iPad Pro 13-inch (M5)'"])
case("app", "archive dry-run with ${BUILD_DIR}", ["archive", "--dry-run"], app, env=dict(ios, BUILD_DIR="/tmp/out"),
     has=["-archivePath /tmp/out/SampleApp.xcarchive", "-configuration Release", "-xcconfig Config/Shared.xcconfig"])
case("app", "lint (swiftlint script)", ["lint"], app)
case("app", "list shows variants and defaults", ["list"], app, has=["  defaults", ":quick", "archive-path: ./build/SampleApp.xcarchive"])
case("app", "doctor passes", ["doctor"], app, env=ios, lacks=["FAIL"], has=["OK    Workspace\tSampleApp.xcworkspace", "OK    Scheme: Core"])

# --- Examples/MacApp: macOS app ---------------------------------------------
case("macapp", "build:quick (macOS, custom formatter)", ["build:quick", "--", "-derivedDataPath", os.path.join(WORK, "MacDD")], mac,
     has=["Build Succeeded"], lacks=["Running pre-build hook"])
case("macapp", "test:core --dest mac", ["test:core", "--dest", "mac", "--", "-derivedDataPath", os.path.join(WORK, "MacDD")], mac,
     has=["Test Succeeded"])
case("macapp", "build:rosetta dry-run", ["build:rosetta", "--dry-run"], mac, has=["-destination platform=macOS,arch=x86_64"])

# --- Examples/Monorepo: members ---------------------------------------------
case("monorepo", "list shows members", ["list"], mono, has=["members:", "core  → Packages/Core", "build, test", "network  → Packages/Network"])
case("monorepo", "build --all skips the root", ["build", "--all"], mono, has=["==> root (skipped: no 'build')", "==> core", "==> network"])
case("monorepo", "test --all skips network", ["test", "--all"], mono, has=["==> network (skipped: no 'test')", "passed"])
case("monorepo", "member command", ["core/test"], mono, has=["passed"])
case("monorepo", "--members selects", ["build", "--members", "network", "--dry-run"], mono, has=["==> network"], lacks=["==> core", "==> root"])
case("monorepo", "lint --all --continue", ["lint", "--all", "--continue"], mono, has=["==> root"])
case("monorepo", "doctor checks members", ["doctor"], mono, has=["OK    Member: core\tPackages/Core", "OK    Member: network"], lacks=["FAIL"])
case("monorepo", "unknown member", ["ghost/build"], mono, code=1, has=["Unknown member 'ghost'. Available members: core, network."])

# --- edge cases and errors (temporary fixtures) ------------------------------
edge = fixture("edge", {
    "xc.yaml": """settings:
  formatter: "sed s/^/FMT:/"
commands:
  fails:
    run: "exit 3"
  hookfail:
    run: "echo should-not-run"
    hooks:
      pre: "exit 2"
  ask:
    run: 'read name; echo "hello $name"'
  root:
    run: 'echo "root=$XC_ROOT"'
  where:
    run: "true"
    hooks:
      pre: "echo pre-ran"
      post: "echo post-ran"
  build:
    scheme: X
  sym:
    scheme: X
    extra-args: ["SYMROOT=${XC_ROOT}/Build"]
  empty:
    run: "${UNSET_VAR_FOR_SMOKE}"
members:
  ok: ok
  bad: bad
""",
    "ok/xc.yaml": 'commands:\n  fails:\n    run: "echo member-ok"\n',
    "bad/xc.yaml": "project: a\n",
    "deep/nested/.keep": "",
})
case("edge", "failing script is a command error", ["fails"], edge, code=1, has=["Error: Command 'fails' exited with code 3."], lacks=["Hook"])
case("edge", "failing pre hook stops the command", ["hookfail"], edge, code=1,
     has=["→ Running pre-hookfail hook...", "Error: Hook 'pre-hookfail' failed with exit code 2."], lacks=["should-not-run"])
case("edge", "hooks run in order", ["where"], edge, has=["→ Running pre-where hook...\npre-ran\n→ Running post-where hook...\npost-ran"])
case("edge", "stdin reaches scripts", ["ask"], edge, stdin="Alex\n", has=["hello Alex"])
case("edge", "XC_ROOT from a subfolder", ["root"], os.path.join(edge, "deep/nested"), has=[f"root={edge}"])
case("edge", "XC_ROOT in config values", ["sym", "--dry-run"], os.path.join(edge, "deep"), has=[f"SYMROOT={edge}/Build"])
case("edge", "stale XC_ROOT is overridden", ["root"], edge, env={"XC_ROOT": "/stale"}, has=[f"root={edge}"])
case("edge", "custom formatter applies", ["build", "--", "-version"], edge, has=["FMT:Xcode"])
case("edge", "--raw overrides custom formatter", ["build", "--raw", "--", "-version"], edge, has=["Xcode"], lacks=["FMT:"])
case("edge", "empty expansion stays a script", ["empty", "--dry-run"], edge, lacks=["xcodebuild"])
for ref, reason in [("core/", "missing a command name"), ("", "missing a command name"),
                    (":release", "missing a command name"), ("fails:", "missing a variant name after ':'")]:
    case("edge", f"invalid ref {ref!r}", [ref], edge, code=1, has=[f"Invalid command '{ref}': {reason}."])
case("edge", "member path with --all", ["ok/fails", "--all"], edge, code=1, has=["use either member/command or --all/--members, not both"])
case("edge", "fan-out fail-fast", ["fails", "--all"], edge, code=1, has=["Failed in 1 member(s): root."], lacks=["member-ok"])
case("edge", "fan-out --continue", ["fails", "--all", "--continue"], edge, code=1,
     has=["member-ok", "==> bad: Member 'bad': Invalid xc.yaml", "Failed in 2 member(s): bad, root."])
case("edge", "broken member", ["bad/x"], edge, code=1, has=["Member 'bad': Invalid xc.yaml: No commands defined."])
case("edge", "doctor exits 1 on failures", ["doctor"], edge, code=1, has=["FAIL  Member: bad", "Some checks failed."])

# Outside the repo: under .build/smoke, xc would walk up and find this repo's xc.yaml.
nocfg = os.path.realpath(tempfile.mkdtemp(prefix="xc-smoke-nocfg-"))
case("edge", "no xc.yaml anywhere", ["build"], nocfg, code=1, has=[f"No xc.yaml (or xc.yml) found in {nocfg} or any parent directory."])
case("edge", "doctor without xc.yaml", ["doctor"], nocfg, code=1, has=["FAIL  xc.yaml\tNot found. Run 'xc init' to generate one."])
shutil.rmtree(nocfg, ignore_errors=True)
yml = fixture("yml", {"xc.yml": 'commands:\n  hi:\n    run: "echo from-yml"\n'})
case("edge", "xc.yml is accepted", ["hi"], yml, has=["from-yml"])
badyaml = fixture("badyaml", {"xc.yaml": "commands: [unclosed\n"})
case("edge", "invalid YAML", ["list"], badyaml, code=1, has=["Invalid xc.yaml:"])
verbose = fixture("verbose", {"xc.yaml": 'settings:\n  verbose: true\ncommands:\n  hi:\n    run: "echo hi"\n'})
case("edge", "settings.verbose prints the command", ["hi"], verbose, has=["$ echo hi\nhi"])

# --- init ----------------------------------------------------------------------
init_pkg = fixture("init-pkg", {})
shutil.copytree(pkg, init_pkg, dirs_exist_ok=True, ignore=shutil.ignore_patterns("xc.yaml", ".build", ".swiftpm"))
case("init", "package", ["init"], init_pkg, has=["Created xc.yaml", "Swift Package", "Default scheme: SamplePackage"])
case("init", "refuses to overwrite", ["init"], init_pkg, has=["xc.yaml already exists in this directory."])
case("init", "generated config works", ["list"], init_pkg, has=["  build", ":release", "archive-path: ./build/Package.xcarchive"])
init_ws = fixture("init-ws", {})
os.symlink(os.path.join(app, "SampleApp.xcworkspace"), os.path.join(init_ws, "SampleApp.xcworkspace"))
case("init", "workspace (iOS)", ["init"], init_ws, has=["Workspace: SampleApp", "Default scheme: SampleApp", "Platform: iOS"])
case("init", "empty folder", ["init"], fixture("init-empty", {".keep": ""}), has=["No project detected", "Platform: unknown"])

# --- steps ----------------------------------------------------------------------
steps = fixture("steps", {"xc.yaml": """commands:
  a:
    run: "echo ran-a"
  b:
    run: "echo ran-b"
  bad:
    run: "exit 1"
  pkg:
    scheme: X
  gate:
    steps: [a, bad, b]
  ok:
    steps: [a, b]
  dry:
    steps: [a, pkg]
  typo:
    steps: [a, nope]
  loop:
    steps: [a, loop2]
  loop2:
    steps: [loop]
  wrapped:
    steps: [ok]
    hooks:
      pre: "echo chain-pre"
"""})
mixed = fixture("steps-mixed", {"xc.yaml": 'commands:\n  gate:\n    run: "make"\n    steps: [a]\n'})
case("steps", "repo gate runs lint, build, test", ["gate"], REPO,
     has=["==> lint", "==> build", "==> test", "✓ lint", "✓ build", "✓ test"], timeout=900)
case("steps", "passing chain", ["ok"], steps, has=["==> a\nran-a\n==> b\nran-b", "✓ a", "✓ b"])
case("steps", "failing step stops the chain", ["gate"], steps, code=1,
     has=["✗ bad", "Command 'bad' exited with code 1.", "- b    not run", "Error: Step 'bad' failed."], lacks=["ran-b"])
case("steps", "--continue runs the rest", ["gate", "--continue"], steps, code=1, has=["ran-b", "✓ b", "Error: Step 'bad' failed."])
case("steps", "--dry-run prints each step", ["dry", "--dry-run", "--dest", "platform=macOS"], steps,
     has=["==> a\necho ran-a", "==> pkg\nxcodebuild pkg -scheme X -destination platform=macOS"], lacks=["✓", "\nran-a"])
case("steps", "unknown step fails up front", ["typo"], steps, code=1, has=["Step 'nope' of 'typo': Unknown command 'nope'."], lacks=["ran-a"])
case("steps", "loop fails up front", ["loop"], steps, code=1, has=["Steps of 'loop' loop: loop → loop2 → loop."], lacks=["ran-a"])
case("steps", "args after -- rejected", ["ok", "--", "-x"], steps, code=1, has=["arguments after -- can't be passed to a steps command"])
case("steps", "hooks wrap the chain", ["wrapped"], steps, has=["→ Running pre-wrapped hook...\nchain-pre\n==> ok"])
case("steps", "steps mixed with run: rejected", ["gate"], mixed, code=1, has=["Command 'gate' combines 'steps' with run."])
case("steps", "list shows steps", ["list"], steps, has=["steps: a, bad, b"])
case("steps", "fan-out runs steps per target", ["gate", "--all", "--dry-run"], os.path.join(REPO), code=0, has=["==> root", "==> lint"])

sigint_case()

passed = sum(1 for r in results if r[2])
print(f"\n{passed}/{len(results)} passed")
for group, name, ok, took, problems, log in results:
    if not ok:
        print(f"  FAIL {group}/{name}: {'; '.join(problems)}\n       log: {log}")
sys.exit(0 if passed == len(results) else 1)
