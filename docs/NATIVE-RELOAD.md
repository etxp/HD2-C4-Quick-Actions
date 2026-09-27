> Historical development note. The accepted 1.1 behavior and current verification scope are documented in [VALIDATION.md](VALIDATION.md). Private captures referenced below are not distributed.

# Auto reload: verified path and limits

This describes the dev.8 feature with the dev.8.1 startup, dev.10 backpack and dev.11 timing fixes,
not live acceptance. All new code stays in
this project; the native image and disassembly are private local evidence.
Recorded RVAs below identify that evidence, never runtime build/version gates.
The runtime resolves masked signatures and validates cross-references.

## Original native path

| Local capture symbol | RVA | Evidence / use |
| --- | --- | --- |
| Reload command | 0x774b60 | `(manager, uint32 weapon_id, bool force)`; `force=false` retains native eligibility |
| Reload eligibility | 0x775580 | `(manager, weapon_id, bool, bool)`; both optional bypass arguments false |
| Reload config | 0x4fd220 | Per-entity override map +0x60 / data +0xa0; otherwise resource template |
| Reload template | 0x4fce20 | Owner +0xf12800, capacity 498, 80-byte rows; ability at +4 |
| Reload in progress | 0x776010 | Resolves weapon owner, compares owner's active ability with reload config |
| Ability tick | 0x7c8840 | Scaled native elapsed time at +8, processes phase boundaries using 60.0f |
| C4 Deploy lifecycle | 0x10bb510 | Phase 10 runs native C4 creation/throw; phase 30 requests normal reload |

The manual avatar input path calls the same reload command with force=false.
The command resolves the selected weapon's owner and starts the configured reload
ability on that avatar, retaining the original speed and network/local argument.
It does not use the C4 weapon's own ability ID as the reload ID.

The reload manager is the same component historically named `global_exclusions`
in this project. Its +0x50 flags already participate in C4 native gating. The new
reader reuses that resolved global; tests share the same component and do not
invent a separate reload manager.

The native eligibility function has a special mutating branch for reload ability
0xb17. The reader explicitly rejects that config before using eligibility as a
query. The ordinary C4 path retains original ammo and action gates. Native
eligibility can reject; we do not force acceptance or alter state flags to allow it.

## Timing and interruption

On foot, only a throw started by this mod arms an opportunity. After a native
update returns, the weapon's active Deploy clock must have crossed phase 10 and
must not be paused; a finished Deploy is also eligible for consideration. This
uses native action progress, not a fixed number of milliseconds after clicking.
The native eligibility check still decides when reload can actually start.

In vehicles, wait for the entire Deploy to finish and the dev.7 passenger
reservation to release before offering reload. This preserves the newly tested
passenger sequence rather than cancelling its recovery early.

The second trigger is an observed spare-ammo transition 0 -> positive while the
selected C4 chamber remains empty. Changes while the player is in a blocking UI
are not replayed later. dev.11 may wait for the action already running when the
resupply occurs; replacement actions cancel. Equipping an already empty C4
with existing ammunition is not itself a resupply event.

Each opportunity makes at most one reload request. A native veto may be queried
again for up to 1.5 seconds after the release point; the overall opportunity has
an eight-second expiry. These are cancellation limits, not imposed reload delays.
An existing native reload is never restarted. UI/map/focus changes, weapon or
avatar identity changes, other avatar abilities and detonation take priority.
A queued next throw can benefit from reload; it does not cancel the opportunity.

Once normal reload starts, the engine owns animation, ammunition and cancellation.
The mod does not hold an input, write an ammo counter, lock weapon switching or
restart a reload interrupted by the player. No additional memory writes or
executable-code hooks are introduced in dev.8.

## Validation boundary

Integration fixtures enforce exact call arguments, dynamic reload IDs, local
weapon/owner identity, no pre-release call, no repeated restart, interruption and
passenger ordering. Real captured-code tests validate new signatures, references,
phase scale and code-mutation rejection. No test invokes captured machine code.

Live timing, whether the native eligibility window yields faster recovery, actual
resupply, native reload cancellation, and multiplayer behavior still require a
user test. A missing/changed reload context disables automatic reload for that
context while preserving the existing throw/detonate path.

## dev.8.1 startup correction

Two live dev.8 sessions failed initialization with `compat_literal_changed:fn_reload`
before binding registration. The catalog generator had treated the first four
bytes of an absolute pointer table addressed by LEA as a scalar constant.
The captured reference at reload +0x256 addresses RVA 0x21d7828; its contents
are relocated by the OS and must not be pinned to a previous process's address.

The resolver now verifies the reference's readonly section and eight-byte extent,
then snapshots this process's bytes for subsequent immutable guards. It retains
code signatures, cross-references and genuine float-literal comparisons. The
generator requires explicit review of other LEA references before pinning data.
Captured-code regression reproduces the legacy failure at a different module
base, accepts two relocated pointer values, and still rejects later pointer
mutation and changed 60.0f. Assembled-entry tests confirm both stable MBM action
IDs register and dispatch under those pointer changes. No native code is executed
by these tests; actual startup and automatic reload still need live confirmation.

## dev.9 attempted spare-ammunition correction (superseded)

Live session 20260926T112845Z_001 confirms startup is restored. It contains no
mod reload calls. All 3489 observations of the selected-magazine count are zero,
even when the player has charges in their backpack. On-foot reload is native
engine behavior; it is not evidence that the mod's request path worked.

The previous fixture incorrectly put spare charges into the selected magazine.
The fixture now models the live C4 profile: zero selected-magazine rounds, zero
local reserve, and an external supply resource with charges. Config ability
0xb0b is read dynamically, not required as a hardcoded runtime value.

Readonly derivation (RVAs identify the private capture only):
- Native reserve query 0x744180 reads rounds +0x58, index stride 20, field +0.
  The selected magazine at rounds +0x50 is a separate quantity.
- Reload eligibility 0x775580 uses global 0x3326698, weapon-ID map +0x18,
  data +0x38, stride 0xac, and the unit handle at +0 to find its supply entity.
- Helper 0xfd9980 resolves that handle via owner +0xf2aee0. The map value is
  the entity ID itself, not an index into the entity array.
- The resource counter at global 0x33265e8 uses ID map +0x20, entity registry
  +0x38, data +0x50, stride 8, current amount +0.
- Config +0x3c controls whether helper 0x7761d0 includes external resources in
  the generic reserve query. It is zero for the observed C4. The dev.9 inference that the
  generic supply branch was still used was wrong; see the correction below.

ReloadReader adds local reserve and the linked resource count once each. It
checks entity IDs, the resource registry, count bounds and every traversed read.
The final original reload eligibility query still decides whether those reserves
are available for this action, including native reservation rules. The new
catalog cross-checks the above native paths; no new native calls or writes occur.
Fixtures cover genuine zero-to-positive supply changes, empty backpack veto,
loaded chamber, local reserve, passenger completion, interruptions, and stale or
invalid supply identity. Native-image tests verify the fields and reject code
mutation. Actual resupply and passenger reload remain pending live validation.

## dev.10 equipped-backpack branch and corrected evidence

Live dev.9 session 20260926T114838Z_001 records 1174 verified contexts, all with
resource_counter_absent and zero reserves. The generic unit relation resolved to
the local avatar in every case. No reload was requested by this mod.

The original eligibility control flow is:
- Query ordinary weapon reserves via 0x744180.
- With none, check weapon membership in backpack reload component 0x3326be8
  (map +0x18), then the local owner's inventory component 0x3326738.
- For that path call 0x73b440 with the component, weapon ID and owner avatar ID.
  It calls 0x9a9cc0, which resolves the avatar inventory and returns the equipped
  backpack ID at data +0x50 + index*48 +12. This is the same inventory relation
  already read and identity-checked by ContextReader.
- The helper verifies resource-component membership, backpack type 0x11, the
  compatible backpack definition and minimum resource count. These checks remain
  in the original native eligibility call; the mod does not bypass them.
- The separate generic unit-supply branch at 0x775a00 is gated by the comparison
  at 0x7759f5: config +0x3c equal to zero jumps to 0x775eb0, skipping that branch.
  dev.9 missed that gate. Its documentation and fixture were therefore incorrect.

ReloadReader now follows weapon backpack-component membership to the actual
inventory backpack ID. It checks that entity's registry and reads its resource
counter; a missing backpack is empty. It uses the generic unit relation only
when there is no backpack branch and config +0x3c enables it. The native query
still decides whether an observed count is sufficient and compatible.

The new fixture keeps local and magazine reserves at zero, has the generic
relation point at the avatar with no resource counter, and puts ammunition in a
separate equipped backpack. It covers both config branches, backpack replacement,
missing backpack, native veto despite positive count, and supply-change logging.
Captured-code tests verify the branch gate, helper call and inventory +12 access.
New signatures are readonly validation; there are no new native calls or writes.
Both reported reload cases still need dev.10 live confirmation.

## dev.11 live opportunity lifecycle correction

The retained dev.10 logs now show correct backpack counters (0–6) and 11 on-foot
reload requests. The user reports faster reload, but no successful resupply or
passenger automatic reload. Sort rolling segments by tick, not filename.

Resupply events coincided with active avatar ability 2067. The old controller
returned before arming resupply, losing the zero-to-positive edge. The new
controller arms first and waits for the already-running action to finish. Its
identity is the dynamic ability ID plus nondecreasing native time (+8 in the
existing ability state); there is no hardcoded pickup ability. Different actions,
time reset, invalid time, new UI/map/weapon/focus/MBM interruptions or detonation
cancel. The existing eight-second opportunity limit bounds this deferred work.
A native reload starting during this resupply wait consumes the opportunity;
it is never restarted after cancellation.

Three passenger throw opportunities were cancelled about 500 ms after start
because the engine briefly activated reload while Deploy still owned the seat.
Treating active reload as completed loading lost the post-throw opportunity.
The fix only retains this special opportunity when no avatar action was active
at throw admission and reload began during that same passenger Deploy. It waits
for that reload attempt to end, full Deploy to end, lease release and a stable
seat. If the chamber was filled, discard the opportunity; if still empty, permit
one original non-forced reload request. A prior reload, later new reload, clock
reset or player interruption discards the opportunity. A mod-requested reload
always consumes it immediately, so cancelling that reload causes no retry.

Decision events now include fresh avatar/weapon state and reload_sample_at_ms;
older auto_reload events merged stale ActionController fields that could disagree
with the newer snapshot used to choose their cancellation reason. The ammo
observation events in dev.10 already override their avatar fields with fresh data.
No new native calls, code changes, signatures or game-memory writes are added.
Tests replay resupply during an action, subsequent interruption, early transient
vehicle reload, successful native reload, seat transition and bounded requests.
These checks do not establish live success of the two outstanding cases.


## dev.12 passenger idle-gap correction

The user accepted dev.11 on-foot automatic reload but reports passenger failure.
Retained session C4DualInput_20260926T121931Z_001 has four passenger requests,
at ticks 9307, 9599, 9817 and 10662, all on the lease-release tick. Fresh decision
fields show transition=false and both weapon/avatar actions inactive. The later
samples show retract transition, no loaded chamber and unchanged spare ammo.
Two visible transitions occur about 49/48 ms after the request. This supports a
request/retract timing conflict; it does not prove every native cancellation cause.

Do not equate one idle sample after releasing +30 with a completed return.
Passenger reload now requires +30 clear, pending node +18 and animation +20 both
INVALID, and the same lean flag across at least three eligible observations
spanning 250 ms. The pending fields were already checked by PassengerHold.ready.
Any transition, lean change, active action or owned lease clears the stability
window. This is a scheduling debounce, not a substitute for native eligibility
or an assumed animation length. Stable leaned-out and seated-in states qualify;
there is no model/seat allowlist and no forced return. On-foot timing is unchanged.

Fresh reload_seat_leaned, reload_seat_idle, reload_seat_stable_ms and sample count
accompany decisions, avoiding stale ActionController seat snapshots. Existing
player interruptions, eight-second opportunity expiry, native eligibility and
single-request behavior remain. A cancelled mod reload is never retried.
Only Lua scheduling and existing readonly relation interpretation change;
no native ABI, executable memory, game writes or new signatures are introduced.
Tests exercise the observed idle gap followed by retract, stable held lean-out,
pending animations, lean changes, low update frequency, passenger resupply,
interruptions during settling and expiry. Passenger success still needs live testing.

## dev.14 one dismount recovery opportunity

`PassengerReloadRecovery` remembers an unfinished passenger throw/resupply load
using the validated avatar, C4 entity and world-owner identity before the seat
suffix is added. This carries no saved native addresses/capabilities. The normal
reload intent is still cancelled on interruption. A fresh opportunity may be
created after leaving the vehicle, while the same C4 is empty with spare ammo.
It requires three idle on-foot observations spanning 250 ms and the current
normal reload checks. Existing bounded eligibility retries apply. This request
is consumed once; interrupting it does not restart it again.

Map/UI observations preserve the raw seated flag, even when seat admission is
vetoed. They cannot masquerade as dismount. Completed loads, changed identity,
other selected weapons, driver seats and zero spare ammunition revoke recovery.
The on-foot window expires after eight seconds if blocked/busy; vehicle waiting
itself has no timeout. Failed context reads cannot authorize a reload. A throw
whose chamber is consumed after its start callback is also tracked. No new
native reload ABI or forced-reload option is introduced.
