# Contributing

Start with [building](docs/BUILDING.md), [architecture](docs/ARCHITECTURE.md) and [validation](docs/VALIDATION.md). Code and documentation contributions are welcome under the MIT license.

Edit source modules and assembly scripts, regenerate the runtime and run `python -B scripts/check_automatic.py`. Keep a clear distinction between mock checks and actual game observations. A new game build or altered native entry point requires new layout verification rather than simply changing the accepted hash.

For bug reports, include the game build, mod/runtime version, mouse or controller profile, firing mode and a short reproduction sequence. Record whether the issue followed reload, an equipment switch or a menu/focus transition. An F7 marker can help locate the relevant point. The local collector writes under `local-evidence/`; the shared traces in this repository demonstrate the fields useful for a public report.

Gameplay changes should retain the native eligibility, local ownership and restoration checks. Packaging/name/documentation changes should demonstrate whether the runtime payload changed. The current public package intentionally matches the user-tested EXP06 payload byte for byte.
