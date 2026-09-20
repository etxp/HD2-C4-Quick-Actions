# Changelog

## 0.6.0 — 2026-09-20

First public package named **HD2 C4 Quick Actions**, preserving the tested EXP06 runtime.

- Automatic activation while the local C4 is equipped; F6 is no longer required.
- R reload pauses custom input instead of permanently disabling it.
- Focus/cursor/input guards resume after a released baseline and discard paused pending actions.
- Mouse RMB/LMB, Xbox LT/RT and PlayStation L2/R2 mapping retained.
- MIT-licensed source, tests, portable packaging tools, research notes and sanitized traces included.

## Research stages

- EXP05: engine gamepad profiles, analog hysteresis, exact guard-key diagnostics and four-part rotating logs. Xbox basic operation confirmed by the tester; R reload disarm identified.
- EXP04: physical mouse mapping with scoped original Fire suppression/restoration. Basic gameplay confirmed.
- EXP03: native Deploy/Detonate lifecycle, eligibility, action lock and bounded pending. Cross-mode actions confirmed; reload pre-trigger expansion was not pursued.
- EXP02: local weapon, ownership, mode and descriptor observation.
- EXP01: mouse input and API observation.

See [research](research/README.md) for the original requirements and stage reports.
