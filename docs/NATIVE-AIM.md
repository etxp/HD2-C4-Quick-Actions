> Historical development note. The accepted 1.1 behavior and current verification scope are documented in [VALIDATION.md](VALIDATION.md). Private captures referenced below are not distributed.

# dev.13 Aim overlap suppression

Aim policy reads MBM v2's `ModBindingsMenu.assignments` for the two registered
stable action IDs. It does not allocate dormant slots, edit configuration, poll
physical devices or generate C4 activations. `MBMBindings` remains the only
throw/detonate input source. Missing assignment metadata disables this feature
without disabling existing C4 controls.

The current native bindings map supplies each action's 20-byte mappings.
The original readonly mapping getter selects the native preferred-device Aim
mapping. Physical identity follows the native device/type/control mask, with
compatible explicit/wildcard device slots. Button trigger types are verified
against both copies in a mapping. Release (1) and LongRelease (7) throw retain
Aim; matching detonation always suppresses Aim, including release detonation.
Other Aim bindings on the same device and device switching need live validation:
the original inhibitor acts on the whole Aim action, not an individual mapping.

## Original native calls and evidence

All RVAs here identify the local immutable analysis capture, not runtime
addresses or game-version gates. Runtime masked signatures, relative references,
switch tables and literal values resolve and verify the actual functions.

| Capture RVA | Meaning / ABI |
| --- | --- |
| `0x585b80` | Packed action -> index; verified group switch table |
| `0x12f9540` | `void *mapping(owner, uint64 action, bool fallback)` |
| `0x12fd250` | `void inhibit(owner, uint64 action, uint32 mode, float duration)` |
| `0x12fd3b0` | `void unblock(owner, uint64 action)`; clears record mode only |
| `0x12fd820` | Inhibition lookup used by native input update |
| `0x12fa32e` | Nonzero mode + zero/future expiry marks input inhibited |
| `0x12fbb59` | Inhibited action receives two 16-byte zero stores |
| `0xa4129c` | Avatar Aim reads packed action `0x800000002` |
| `0xab9f40` | Named trigger parser: Release=1, LongRelease=7 |

Win64 inhibit arguments are RCX=owner, RDX=action, R8D=mode, XMM3=duration.
Mode 1 inhibits the action until explicitly cleared. Duration -1 produces expiry
zero. Mode 2 has different release behavior and is not used here.
Owner offsets: binding map `0xa7ad0`; inhibit count `0xa7d34`; record array
`0xa7d38`; inhibit lookup map `0xa9b40`. Each 24-byte record stores mode at +0,
packed action at +4 and expiry at +16. Aim key is `0x20008`.

## Ownership and restoration

Acquisition requires verified local C4 context, released native Aim, unchanged
snapshots, a successful flushed log record and no existing external inhibition.
The original native call owns map insertion; Lua never writes mapping/camera
data or executable memory. Only original Aim input calls are added.

Cleanup checks input-owner identity and the complete record bytes before
unblocking. Changed inhibition from the engine or another mod is preserved.
The gate runs before and after the original update and restores on UI/map,
focus loss, weapon/context change, errors and shutdown. An acquisition recorded
as pending also attempts cleanup if the post-call read fails. Failed reads or
code verification forbid further mutation until verification succeeds.

The accepted passenger lean reservation and automatic reload are unchanged.
Driver-seat support was removed from scope. No upstream MBM source is included
in the distributable.

## Validation boundary

`tests/aim_fixture.lua` checks the native-call arguments and synthetic input
inhibition. Runtime cases cover all nine trigger modes for throw/detonation,
device identity, remapping, cleanup, external ownership, failure recovery and
passenger throw/reload. Captured-native tests independently check Aim identity,
ABI instructions, suppression path and literal verification.

These tests do not execute the game engine. Camera behavior, callback ordering,
mixed-device timing, passenger visuals and running-game integrity compatibility
remain unverified until user gameplay testing.

## dev.14 native Fire input

The same guarded input-inhibition owner is instantiated independently for native
Fire (`group=2`, action 9, packed `0x900000002`, key `0x20009`). The original
weapon-bit gate remains in place. Fire inhibition covers the avatar input read
that the weapon-bit gate did not stop. The capture's `0xa45514` loads this action
and `0xa45535` reads the processed avatar input; runtime resolves this fragment
as `fn_fire_input_read`. Both Aim and Fire masks have separate ownership checks
and cleanup. No new executable mutation or sprint flag write is introduced.

Fire inhibition does not need MBM's assignment file: the accepted policy already
reserves C4 native Fire for MBM-only control. MBM's separate dormant actions
continue to evaluate their actual mappings, including release/hold triggers.
The synthetic avatar consumer checks that suppressed Fire does not reach its
locomotion branch while MBM still throws. The observed live sprint interruption
is consistent with this route but this offline evidence is not proof of the
actual animation cause or of the live fix.
