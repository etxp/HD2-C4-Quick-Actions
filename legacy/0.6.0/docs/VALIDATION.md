# Validation record

## Current public package

Version **0.6.0**, based on the user-tested runtime **0.6.0-exp06**, game build **24826606**. The public packaging changes its display name and documentation, while retaining these exact runtime bytes:

`4134de7cb71ff39a738c13122dc23fe1ec09535397d1e455efb7ab5f687cdb40`

The tester reported that the automatic version appeared to work normally. This confirms basic operation in the tested setup, not every possible device, menu or multiplayer case.

## Latest automatic session

The [sanitized EXP06 trace](../research/traces/exp06-automatic.jsonl) preserves 1,201 event records in order:

| Observation | Result |
| --- | --- |
| Deploy calls / native completions | 31 / 31 |
| Detonate calls / native completions | 52 / 52 |
| Recorded action/probe faults | 0 |
| Permanent feature-disarm events | 0 |
| R fresh press records | 5 |
| Cursor-visible pause transitions | 6 |
| Focus-loss pause transitions | 2 |
| Gameplay-state transitions | 14 |
| Input press records | LMB 79, RMB 32, RT 10, LT 10 |

All 83 called actions in this session used the selected Deploy mode; 52 Detonate actions therefore also have opposite-mode native lifecycle evidence. The earlier experiment established both selected modes; this session alone does not re-test both modes.

Four chamber-blocked, two control/native-state and one pending-coalescing rejections were recorded. These are recorded admission/queue outcomes, not action faults. Counts of presses need not equal calls because native state and the action lock still apply.

Observed native completion is separate from visual throw/explosion confirmation. The tester's broad success report provides the gameplay confirmation for this session; exact backpack consumption, network replication and every pause case were not separately annotated.

## Reload fix and controller baseline

The [EXP05 reload trace](../research/traces/exp05-reload.jsonl) shows a fresh R press and `capture=false`, `reason=menu_key_edge`, at the same tick **6941**. That version treated reload as permanent disarm. The automatic version changes this to a transient pause. The earlier [controller trace](../research/traces/exp05-controller.jsonl) contains Xbox inputs and successful native lifecycles, supported by the tester's Xbox success report.

Sanitization preserves event order and diagnostic/action fields while removing session names, timestamps, paths, entity identities, pointers and memory snapshots. Its field allowlist and hashes are in the [trace manifest](../research/traces/manifest.json). Raw private logs are not bundled; sanitized traces are not byte-identical originals.

## Offline checks

Run `python -B scripts/check_automatic.py`. The public checkout runs the same **159 checks**, covering automatic activation, empty→supply→reload recovery, held controls, mouse/Xbox/PS profiles, both firing modes at simulated 30/60/144 Hz, pending cancellation, native gates, restoration, callback/log failures, rolling logs and collection.

These are synthetic-memory/mock-native checks, not game execution. The [machine-readable result](../evidence/automatic-offline-tests.json) includes commands, outputs and input hashes. The [package report](../evidence/public-package.json) checks archive contents and exact source bytes.

## Remaining scope

- PlayStation hardware, all controller models and all connection methods.
- Multiplayer host/client and latency scenarios.
- Full sprint/dive/vault/stagger/death interruption matrix.
- Every menu/chat/overlay state, especially those without a visible cursor.
- Builds other than the tested game module.

Historical notes retain the conclusions known at each stage and may say “pending” for a case later tested. This document is the current release status.
