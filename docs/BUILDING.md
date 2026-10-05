# Building 1.13.1

Run commands from the repository root. Requirements: Python 3.10+, LuaJIT 2.1 and, for packaging, `libdeflate-gzip`. Python scripts use the standard library. No game installation is needed for the default tests or package build.

## Offline regression checks

```bash
python3 scripts/check.py
```

This assembles the runtime and catalogs, generates a synthetic native-memory fixture, checks Lua compilation and runs the runtime, collision, mode-label and contact-action suites. The complete gameplay suite runs four times: Off and Verbose diagnostics, each against the historical byte-granular fixture memory and against page-granular memory (`tests/test_runtime.lua off pages`), where guards on one page are compared with a single read as in a real process. Generated files go under ignored `private/`; the check report goes to ignored `evidence/checks.json`. Native calls are mocked. The fixed iterator contract fixture does not read or execute captured game code.

`src/` contains the 1.13.1 runtime, derived from release 1.13. Edit modules and `entry.lua.in`, then assemble through the check command; do not edit generated Lua files directly.

## Packaging helper

Obtain the external helper separately. Its pinned commit identifies packaging tools, not a required game or loader-runtime version:

```bash
git clone https://github.com/CowboyBingus/BingusSharedLoader.git vendor/BingusSharedLoader
git -C vendor/BingusSharedLoader checkout 836427cef78b8a67cf771c1f16291d93be921744
python3 scripts/package.py --loader vendor/BingusSharedLoader
python3 scripts/check_package.py --loader vendor/BingusSharedLoader
```

Both package commands verify helper-file hashes from `dependencies.lock.json` before importing or executing them. An existing matching checkout can be supplied instead. Runtime users still need Bingus Shared Loader v17+ and official Mod Bindings Menu v2+, both with API 1.

Output: `dist/HD2-C4-Quick-Actions-1.13.1.zip`. The check validates ZIP integrity, V1 manifest fields and Include folders, GUID, version consistency, hashes, archive resources and Lua catalog loading. It does not deploy into a game or invoke an installed manager. The separate local manager integration checks are documented in `docs/VALIDATION.md`.

The public ZIP directly contains `manifest.json`, `README.txt`, `LICENSE.txt`,
and three patch archives (`.patch_0`, `.patch_1`, `.patch_2`) with their sidecars.
The V1 manifest has no Options field; both managers deploy the complete package.
The entry is the 1.13.1 runtime. The configuration selects Off; Summary/Verbose variants remain local developer build artifacts and
are not included in the public ZIP. No diagnostic files or profiling data are
written by this package. The old diagnostic-choice ZIP is withdrawn.

Portable measurements after running the checks:

```bash
luajit tests/benchmark_runtime.lua private/build/c4_quick_actions.off.lua 240
python3 scripts/soak_check.py
luajit tests/benchmark_contact.lua
```

These use synthetic memory and mocked native calls, not real-game FPS. CPU and
allocation measurements include fixture overhead. The three-way comparison times
unmetered updates and counts reads in a separate pass, warming both paths. `benchmark_contact.lua baseline`
is a local comparison convenience requiring the preserved project-root 1.11 source;
the normal benchmark has no such dependency. Local measurement evidence stays in the project workspace. Do not include
private captures or manager backends in releases.

## Dependency contracts

`scripts/check.py` runs the gameplay suite a third time with a Mod Bindings Menu
v2.2-style table (`poll`, `revision`) and `tests/test_mbm_contract.lua`, which
covers both menu generations, registration retries and both assignments file
formats. When the Mod Bindings Menu v2.2 source is available (set
`MBM_V22_SRC` to its `src/` folder holding `poll.lua`, from
https://github.com/CowboyBingus/ModBindingsMenu/releases/tag/v2.2), the same test
also runs that release's real `poll.lua` against a simulated input owner.

```bash
python3 scripts/check_wine.py --lua-dll PATH/TO/lua51.dll --baseline ../../releases/1.13/src
```

runs `tests/test_ffi_names.lua` in the game's own LuaJIT under Wine against the
real kernel32/user32 on its own memory: with nothing declared first, with the six
plain declarations of Bingus Shared Loader v18/v19, and with another mod's
conflicting declarations of the same Windows functions. The DLL stays private.

## Optional maintainer research

`python3 scripts/check.py --with-native-capture` additionally runs `prepare_capture.py` and `test_capture.lua`. It requires a separately obtained local capture under `private/native/current/`; this capture is deliberately absent from the repository. Addresses asserted in that test describe its historical fixture, not runtime version restrictions. The default test command does not need it.

`analyze_flight.py` and `analyze_vehicle_throws.py` are historical local-log analysis tools, not build prerequisites. Read their arguments and expected input paths before use; no personal logs are distributed for them. `tests/arsenal_*.cjs` preserve the original integration fixtures and require an externally supplied manager backend and configuration. They are not part of portable default tests.

## Optional comparison against 1.12 and 1.12-opt.2

These commands need assembled builds of earlier versions (their ignored
`private/build` output) under `optimization/1.12`, `optimization/1.12-opt.2` and
`optimization/1.12-lean.1` of the complete project workspace. They are not part
of this source tree; the default checks do not need them.

```bash
python3 scripts/differential.py
```

runs identical scripted sessions through this build, formal 1.12 and 1.12-opt.2
and requires every native call, data write, input-gate state and native query
count to be identical on every update. `tests/differential_trace.lua` documents
the script and the compared fields.

```bash
python3 scripts/benchmark_comparison.py
python3 scripts/benchmark_comparison.py --memory wine --lua-dll PATH
python3 scripts/summarize.py
```

time alternating 1.12 / 1.12-lean.1 / current updates and count reads in a
separate pass. The Wine form uses a locally available game Lua DLL in an
isolated process with real `ReadProcessMemory` on its own invented pages; the
DLL stays private and is not distributed. Neither attaches to a game.

`python3 scripts/build_profile.py --loader PATH` builds the separate diagnostic
test package described in `profile/INSTALL-PROFILE.txt`; `tests/test_profile_build.lua`
checks it after `scripts/build_profile.py`.

`python3 scripts/profile_reads.py --pages` attributes read counts by caller;
`--base ../1.12-opt.2 --label opt2` profiles a preserved build. Its wrappers add
overhead, so its timings must not be used as performance measurements.

`luajit tests/benchmark_contact.lua` covers large/mixed projectile registries,
excluding native event-stream acquisition. `benchmark_runtime.lua ... soak` is a
synthetic retained-heap check, not proof about whole-game memory behavior.
