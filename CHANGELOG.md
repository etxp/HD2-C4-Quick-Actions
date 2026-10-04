# Changelog

## 1.13 — 2026-10-04

Same features and controls as 1.12. The checks behind them need far fewer
memory reads and less per-frame bookkeeping. Measured in the game with the
Watchdog: about 9.9 ms per second with C4 in hand and 3.6-4.4 ms per second
otherwise, against 21.8-27 and 6.8-8.1 for the previous optimisation candidate.
An external report of 1.11 counted about 1,265 reads per update with C4 and 322
with a primary weapon; the diagnostic build of this code line measured 119 and
36. Gameplay accepted by the owner on 2026-10-04.

Promoted from development build 1.12-lean.2 with version metadata and
documentation changes only. Changes since 1.12, in development order:

**1.12-lean.2**

- With diagnostics off, the gameplay guard takes the same decision from the
  same engine calls and UI reads without building the descriptive row and its
  change key on every phase.
- With no label lease and no local C4 selected, mode-label sync returns before
  setting up its protected pass.
- Automatic reload takes its complete observation every 100 ms instead of every
  update while nothing is pending, no ability is active and spare ammunition is
  present. The chamber, reserve and supply records are still reread on every
  update: any change, a throw, an intent, a dismount ticket or an empty spare
  count restores per-update observation in the same update. A context that
  becomes unusable for another reason releases input inhibition up to 100 ms
  later than before. Diagnostic builds keep per-update observation.
- Scripted sessions remain identical to 1.12 and 1.12-opt.2 on every update.

**1.12-lean.1** (live profile recorded 2026-10-04)

- Keep a verified snapshot until one of its guarded bytes changes. Each
  before/after phase rereads every guard once instead of walking the game's
  structures again; a changed or unreadable guard falls back to the full walk.
- Compare guards that share a 4 KiB page with one read. Every guarded byte is
  still compared.
- Rebuild a changed snapshot from the page spans the comparison just read, then
  reread all of its guards from memory as before.
- Apply the same rule to the native input state of the Aim/Fire gates (the
  engine's mapping query still runs every phase), the UI stack image, mode-label
  maintenance and native code verification.
- Skip the mode-label template walk when no local C4 is selected. Formal 1.12
  repeated that walk on every update for players holding another weapon.
- Reuse one read buffer in `WindowsRead`.
- Never retain a walk that met an unreadable address beyond its own phase.
- When guards are both changed and unreadable, the earliest one in walk order
  decides the outcome, exactly as the per-guard check did.
- Capability checks before native calls and data writes still reread memory;
  complete code verification before native gameplay calls is unchanged.
- Tests: complete gameplay suite in Off/Verbose on byte-granular and
  page-granular memory; coalesced comparison versus per-guard comparison on
  random memory; retained snapshot versus new walk on 12,000 random memory
  changes; scripted differential sessions against 1.12 and 1.12-opt.2.

Synthetic measurements, method and limits: docs/VALIDATION.md.

**1.12-opt.2 and 1.12-opt.1** (development candidates, included)

- Share one bounded read-only routing observation among native UI, Fire
  ownership and input suppression per update phase; skip ability, ammunition
  and reload parsing where only routing is needed.
- Exact grouped byte encoding, copied-string pointer decoding and no
  diagnostic-only formatting with diagnostics off.

## 1.12

- MBM-only input, Manual/Contact modes, prone/diving actions, FRV/tank
  passenger throwing and interruptible automatic reload.
- Reduced idle input/context reads; no collision tracking for Manual charges;
  separate full, lean and unit-filtered collision decoding.
- Public package uses Off diagnostics with no debug menu or profiling payload.

## 1.11

- Reuse validated action snapshots within each before/after game-update phase;
  invalidate before native mutations and discard at phase boundaries.
- Skip collision monitoring for Manual-only charges.
- The public package keeps diagnostic logging off and exposes no diagnostic
  installation menu.

## 1.1

- Replace fixed mouse/controller routes with official Mod Bindings Menu v2 bindings.
- Add Manual/Contact detonation modes and manual detonation during flight.
- Support prone/diving transitions and FRV/tank passenger throwing and detonation.
- Keep passengers leaned out through the complete throwing animation.
- Add interruptible automatic reload after throws and resupply, including passenger recovery.
- Suppress overlapping vanilla aim/fire inputs while preserving release-to-throw aiming.
- Block accidental actions in interfaces, map and weapon settings; fix mode changes consuming held C4.
- Resolve native compatibility from checked signatures instead of game-build or whole-file hash gates.
- Keep one V1-manifest ZIP for HD2 Mod Manager 1.3 and HD2 Arsenal.

The GitHub 1.1 update contained source and documentation only. Historical public material is preserved under `legacy/0.6.0/`; previously uploaded binary/assets remain in their original locations.
