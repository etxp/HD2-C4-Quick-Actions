# Validation scope — 1.1

The user accepted the 1.1-dev.18 gameplay baseline, including the weapon-settings input fix. Promotion to 1.1 changed only the mod/catalog version strings in the packaged Lua resources. The release record is `evidence/release-1.1.json`.

User-confirmed behavior includes MBM controls, prone/diving transitions, FRV/tank passenger throwing with complete lean-out, ground/passenger automatic reload, input-overlap fixes, Manual/Contact modes, airborne manual detonation, and mode switching without consuming held C4. This does not claim a complete multiplayer, controller-hardware or every-vehicle test matrix.

The development release record reports 435 offline checks, V1 schema validation and actual Arsenal converter/deploy/redeploy/remove checks in isolated fixtures. Those checks used local maintainer inputs. They are historical results, not claims that every integration check is reproduced by a public default command. The exact final ZIP was not separately retested in-game after the version-only promotion.

For publication, the portable tests use synthetic fixtures and a fixed iterator contract instead of a private captured file. `scripts/check.py` reports its own check count and explicitly records whether private native-capture checks ran. No game process is attached. The public package checker validates the archive and manifest contract without running either mod manager.

`evidence/publication-1.1.json` records the publication-source comparison, portable test result and rebuilt ZIP/payload comparison. Game runtime modules remain unchanged; public build/test entry points were adapted for a standalone checkout.

No build number or whole-game hash enables runtime behavior. Missing, ambiguous or changed native signatures and incompatible API contracts can still disable functionality. Future game changes require fresh validation rather than removing those checks.
