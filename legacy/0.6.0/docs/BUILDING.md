# Building and validating

Use Python **3.10+** and **LuaJIT 2.1**. The Python build/test tools use the standard library. The Lua tests simulate Windows APIs, game memory and native calls; they do not start the game. The assembly and test commands operate relative to this checkout, without the original developer's home directory.

## Validate the source

From the repository root:

```bash
python -B scripts/check_automatic.py
```

This assembles the current runtime and the earlier mouse/gamepad regression targets, runs the checked-in suites and records source/input hashes in `evidence/automatic-offline-tests.json`. The current reviewed suite has 159 passing checks. No loader checkout or game installation is needed for these tests.

The small `evidence/*-layout.json` inputs contain the tested module hash and native signature bytes required by the source and synthetic fixtures. They do not require loading the original game's binary to run these checks.

## Obtain the packaging helper

The helper is an external dependency. Obtain the pinned commit from its upstream repository:

```bash
git clone https://github.com/CowboyBingus/BingusSharedLoader.git vendor/BingusSharedLoader
git -C vendor/BingusSharedLoader checkout 836427cef78b8a67cf771c1f16291d93be921744
python -B scripts/build.py --loader vendor/BingusSharedLoader
```

An existing checkout at any location can be passed with `--loader`. The script checks both helper-file hashes in `dependencies.lock.json` before execution. `vendor/` is ignored by Git and is not part of this source distribution.

The result is `dist/HD2-C4-Quick-Actions-v0.6.0.zip`, plus its SHA-256 checksum and `evidence/public-package.json`. The package contains one Lua addon, manifest, installation text and MIT license; the loader runtime is separate. The archive parser independently checks that its embedded Lua bytes exactly match the tested source. No files are installed into the game.

## Source layout

- `src/c4_dual_input_auto.lua`: the generated current runtime, retained for direct review and byte comparison with the tested release.
- `src/*_reader.lua`, `action_backend.lua`, `action_controller.lua`: context, eligibility and original action calls.
- `src/weapon_fire_gate.lua`, `fire_gate_windows.lua`: scoped native Fire ownership and restoration.
- `src/gamepad_input.lua`, `mouse_router.lua`, `input_guard.lua`, `gameplay_guard.lua`, `automatic_tick.lua`: physical input and automatic pause/resume.
- `scripts/assemble_*.py`: the existing staged assembly chain. Historical intermediate files and names are retained to reproduce the tested payload and regression targets.
- `tests/`: synthetic fixtures and runnable tests.
- `research/`: historical notes, earlier research scripts and sanitized runtime traces. See its README for external-input requirements.

Edit the component modules and assemblers, then regenerate; changes to a generated Lua file alone are overwritten. If deliberately releasing changed runtime behavior, update the version and reviewed source hash in `project.json`, rerun the tests, then rebuild. A changed native/game layout also needs new review and gameplay testing.

## Collect local runtime evidence

```bash
python -B scripts/collect_actions.py --phase exp06 --log-dir /path/to/CowboyBingus/Helldivers2/Logs
```

Or provide `--source /path/to/C4DualInput_session_part1.log`. The collector reconstructs retained ring segments, writes to the ignored `local-evidence/` directory and keeps test-session boundaries. These local logs may contain machine paths and runtime identifiers; the public research traces use a separate, documented field allowlist.
