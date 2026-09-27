# Building 1.1

Run commands from the repository root. Requirements: Python 3.10+, LuaJIT 2.1 and, for packaging, `libdeflate-gzip`. Python scripts use the standard library. No game installation is needed for the default tests or package build.

## Offline regression checks

```bash
python3 scripts/check.py
```

This assembles the runtime and catalogs, generates a synthetic native-memory fixture, checks Lua compilation and runs the runtime, collision, mode-label and contact-action suites. Generated files go under ignored `private/`; the check report goes to ignored `evidence/checks.json`. Native calls are mocked. The fixed iterator contract fixture does not read or execute captured game code.

`src/` matches the accepted 1.1 runtime source. Edit modules and `entry.lua.in`, then assemble through the check command; do not edit generated Lua files directly.

## Packaging helper

Obtain the external helper separately. Its pinned commit identifies packaging tools, not a required game or loader-runtime version:

```bash
git clone https://github.com/CowboyBingus/BingusSharedLoader.git vendor/BingusSharedLoader
git -C vendor/BingusSharedLoader checkout 836427cef78b8a67cf771c1f16291d93be921744
python3 scripts/package.py --loader vendor/BingusSharedLoader
python3 scripts/check_package.py --loader vendor/BingusSharedLoader
```

Both package commands verify helper-file hashes from `dependencies.lock.json` before importing or executing them. An existing matching checkout can be supplied instead. Runtime users still need Bingus Shared Loader v17+ and official Mod Bindings Menu v2+, both with API 1.

Output: `dist/HD2-C4-Quick-Actions-1.1.zip`. The check validates ZIP integrity, V1 manifest fields and Include folders, GUID, version consistency, hashes, archive resources and Lua catalog loading. It does not deploy into a game or invoke an installed manager. The separate historical manager integration results are documented in `docs/VALIDATION.md`.

The ZIP directly contains `manifest.json`, `README.txt`, `LICENSE.txt`, and `Core/`. Core contains the entry `.patch_0`, catalog `.patch_1`, and their empty `.stream` / `.gpu_resources` sidecars. Install them together. There is no empty Include on the classification parent option.

## Optional maintainer research

`python3 scripts/check.py --with-native-capture` additionally runs `prepare_capture.py` and `test_capture.lua`. It requires a separately obtained local capture under `private/native/current/`; this capture is deliberately absent from the repository. Addresses asserted in that test describe its historical fixture, not runtime version restrictions. The default test command does not need it.

`analyze_flight.py` and `analyze_vehicle_throws.py` are historical local-log analysis tools, not build prerequisites. Read their arguments and expected input paths before use; no personal logs are distributed for them. `tests/arsenal_*.cjs` preserve the original integration fixtures and require an externally supplied manager backend and configuration. They are not part of portable default tests.
