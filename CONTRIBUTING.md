# Contributing

Use Python 3.10+ and LuaJIT 2.1. Follow [BUILDING.md](docs/BUILDING.md), run `python3 scripts/check.py`, and include the result with changes. Packaging additionally requires the separately obtained, hash-checked loader helper and libdeflate-gzip.

Keep gameplay changes separate from packaging/documentation changes. Preserve ownership, native identity, UI and cleanup checks. Do not add executable-memory patches, trampolines or game-build hash allowlists. A changed native contract needs new evidence and gameplay testing.

For reports, include the mod/dependency versions, game version, device/binding activation type, selected mode and steps to reproduce. Mention passenger seat, posture, resupply, weapon switch or interface transitions when relevant. Remove personal paths and identifiers before sharing log excerpts. There is no F7 diagnostic shortcut in this version.

Keep captures, personal logs, recordings, credentials and external source checkouts out of commits. Project-authored contributions use the MIT license. Historical research remains available under `legacy/0.6.0/`.
