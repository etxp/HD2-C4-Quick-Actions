# Working on 1.13

This directory is the formal 1.13 source snapshot (promoted from the
user-accepted 1.12-lean.2 with version metadata and documentation changes only).
Preserve it as release history; start later changes in a new work folder.

MBM-only controls, one V1 HD2MM/Arsenal ZIP with the existing GUID, no
diagnostics menu in the public package, no executable-memory writes, hooks,
protection changes or whole-game build/hash gates. Keep legacy/0.6.0 as
historical material. Public build/test commands: docs/BUILDING.md.

Retained observations:

- Reused solely after every byte guarded has been reread and compared equal. A
  walk that met an unreadable address or made an unguarded read is never
  retained beyond its phase. Do not add an input to a reader without guarding it.
- `cap.same()`, `plan.same()` and `p.same()` at native call and data-write
  boundaries always reread memory; they never use phase spans (`ReadMemo`).
- Phase spans live inside one before/after phase and are discarded by every
  native mutation and owned data exchange. Add new mutators to the wrapped list
  in `ActionBackend`.

Automatic reload interval (Off build only):

- The complete observation may be spaced only while there is no intent, no
  dismount ticket, no active weapon or avatar ability, no interruption, no
  passenger hold and spare ammunition is present, and only while the chamber,
  reserve and supply records reread on every update are unchanged.
- Do not space input sampling, routing, UI vetoes, Contact tracking or any
  observation an action depends on. Do not drop a phase or validate structure
  less often than every phase. Diagnostic builds keep per-update observation.

Do not replace `ReadProcessMemory` with direct pointer reads. The WeaponData
template that holds the Aim permission byte is in a read-only page: do not
write it or change its protection.

Run `python3 scripts/check.py` for portable offline checks; they are not live
tests. Keep private/, vendor/, recordings, credentials and game captures out of
Git. Report offline measurements and live validation separately.
