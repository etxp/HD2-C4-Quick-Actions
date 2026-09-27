# Working on 1.1

- Active runtime: src/. Public build/test commands: docs/BUILDING.md.
- Run python3 scripts/check.py for portable offline checks. Do not claim these are live tests.
- Keep legacy/0.6.0 as historical material. Old build hashes and physical bindings do not apply to 1.1.
- Preserve MBM-only controls and checked native identities. Do not add game-build/hash allowlists.
- No executable-memory patches, trampolines, hooks or protection changes.
- Keep private/, vendor/, recordings, credentials and game captures out of Git.
- Package one V1 ZIP for HD2MM/Arsenal; preserve GUID and all Description fields.
- Do not change runtime code when fixing packaging. Verify payload hashes.
