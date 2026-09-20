# Research materials

The [original PRD](PRD.md) and [historical notes](docs/RESEARCH_REPORT.md) record the progression from input observation to native C4 actions and automatic dual controls. Historical notes describe the state of each experiment; [current validation](../docs/VALIDATION.md) takes precedence for release status.

## Reading order

1. [Requirements](PRD.md), [resource relationships](docs/RESOURCE_MAP.md).
2. [Local context research](docs/NATIVE_EXP02.md).
3. [Native action research](docs/NATIVE_EXP03.md), [initial failure](docs/LIVE_ACTION_FAILURE.md), [successful action tests](docs/LIVE_ACTION_SUCCESS.md).
4. [Mouse Fire routing](docs/NATIVE_EXP04.md), [gamepad design](docs/GAMEPAD_IMPLEMENTATION.md).
5. [R reload diagnosis](docs/LIVE_GAMEPAD_RELOAD_RESULT.md), [automatic activation](docs/AUTOMATIC_IMPLEMENTATION.md).
6. [Current architecture](../docs/ARCHITECTURE.md), [validation and limitations](../docs/VALIDATION.md).

## Available source and data

- `../src/`: complete current modules, generated runtime and earlier generated prototypes.
- `../scripts/`: runnable current assembly, validation, packaging and local collection tools.
- `scripts/`: earlier research/analysis tools retained for methodology review. Set `C4_RESEARCH_WORKSPACE` to a complete research workspace; external inputs can be supplied through `C4_RESEARCH_TOOLS`, `C4_RESEARCH_INSPECTOR`, `C4_RESEARCH_STEAM`, `C4_RESEARCH_CAPTURE`, `C4_RESEARCH_HELPERS`, `C4_RESEARCH_LOGS` and `C4_RESEARCH_GAME_DLL` where used. Defaults written as `<local-home>` are placeholders for separately supplied tools, game inputs and captured data. These historical scripts are not the supported public build commands; the active build does not need those external inputs.
- `tests/`: the complete historical test-source snapshot, including earlier probe/context/action phases. The active `../tests/` directory contains the currently runnable release suite. Earlier entry/collection tests may need the corresponding historical layout and evidence inputs.
- `../evidence/*-layout.json`: module hash and native-signature inputs used by the runnable tests and assembly.
- `traces/`: three sanitized real runtime traces, with event order, counts, input edges, guard transitions and action lifecycles preserved. The manifest documents the exact retained fields and hashes.

Whole game binaries, extracted assets, full native disassembly captures and third-party checkouts are not included. References and pinned upstream versions are in [THIRD_PARTY.md](../THIRD_PARTY.md). Historical document links to unbundled local artifacts are shown as text rather than broken download links.

This release opens the implemented runtime, test fixtures, assembly method and diagnostic reasoning. It does not imply that untested platforms, game updates or multiplayer cases have been validated.
