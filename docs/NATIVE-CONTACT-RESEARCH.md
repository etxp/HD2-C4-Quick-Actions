> Historical development note. The accepted 1.1 behavior and current verification scope are documented in [VALIDATION.md](VALIDATION.md). Private captures referenced below are not distributed.

# Manual/contact implementation — dev.17

Status: implemented for gameplay testing, not live accepted. dev.14 is the last
accepted gameplay baseline. Private snapshots preserve earlier research source.
`evidence/dev16-live-review.json` records the collision observations used here.

## Live evidence and identity correction

The completed dev.16 session produced six owned charges. Five matched physical
collision events, visible before and after Lua updates. The third (entity 487)
was manually detonated in flight with no collision event or sticky state change;
the user confirmed that example. All 220 sampled stream snapshots were stable.
No contact explosion was enabled in that research package.

Entity +12 is the numeric engine Unit ID (verified by the native entity→unit
function). It is not a Lua Unit object. The remote manager's owner link stores
a different native reference, resolved through entity_unit_map. dev.15/16 scene
position attempts confused these types; Unit.id also did not return the expected
numeric ID. dev.17 does not use those position APIs or infer contact from speed,
attachment or disappearance. Historical positional claims are superseded.

## Verified native calls

Original Detonate lifecycle phase 15 calls the remote manager's owner batch
function with (manager, weapon_entity_id). It filters owned charges and preserves
native networking and its normal timing. The new airborne path calls this same
function only after projectile release while Deploy remains active. It leaves
the throw lifecycle/passenger hold intact. Earlier manual input may wait for
release; UI/map/ragdoll interruption still cancels player requests.

The native collision branch calls the single-projectile explosion function with
(explosive_manager, charge_entity_id, invalid_source_id, null_source_info).
The invalid source sentinel is read from the same resolved global as the
original caller, not assumed. Its second network-state byte records a detonation
request. ContactActions uses these exact four arguments. Contact mode calls this
single-charge path, not the remote batch; manual mode uses ordinary detonation.
The authority bit, complete entity generation and owning weapon are rechecked
before each call. Native return alone is not visual explosion confirmation.

Private disassemblies under private/native/contact-* establish the call sites,
ABI, maps and state layouts. Their capture RVAs are evidence labels, never
runtime lookup or game-version admission. The optional 17-node masked catalog
resolves current functions, globals, cross-references and label switch data;
immutable code verification is repeated before native effects. No executable
writes, hooks, allocations or page-protection changes are introduced.

## Physics events and per-charge modes

CollisionEvents retains the read-only dev.16 implementation. Verified engine
getter/iterator bodies establish used-byte length, buffer pointer and records:
u32 payload_length, u32 type, payload. The reader does not invoke these methods
or change the native cursor. Header/content/world are checked for stability;
capacity garbage, malformed sizes and foreign event types are rejected.
Type 0x9e1f9efd represents the observed collision records; payload kind 2 is
excluded. Overlap type 0x7dc7cfba is not treated as a contact.

The original collision dispatcher also validates both actor handles. This
module does not claim to duplicate those actor calls: it consumes a stable
historical physical collision notification and freshly validates the owned C4
entity, unit generation, authority and explosive registry. The other actor need
not remain alive after its physical contact. Neither proximity nor attachment
is substituted for an event. Both event sides are considered; self pairs and
repeated manifolds/samples cannot cause repeated detonation.

ContactController snapshots the native selector and known charges immediately
before an accepted throw. After native start is observed it permits one new
owned charge within two seconds, freezing Manual/Contact for that charge. Zero
new charges expires; ambiguous births disable contact instead of guessing.
Existing charges never become contact charges retroactively. Manual charges
can coexist with Contact charges, including after weapon or UI changes.

The independent ContactReader bounds registries (128), maps/probes, addresses,
individual reads (4096 bytes), total reads and bytes. It validates the full
24-byte weapon/projectile identities, remote registry and owner link, engine
Unit→entity map and explosive registry before exposing capabilities. World,
weapon lifetime, entity generation or authority changes revoke them. Automatic
physics reactions continue when a map/menu blocks player input. Torn stream
snapshots skip a step; invalid ownership/native state fails closed with a log.

Before explosion, another snapshot is taken and all guarded bytes rechecked,
then a pre-call log is flushed and identity rechecked again. The charge is marked
fired before the native call. Native-requested charges are skipped. A native
exception disables contact processing rather than repeating an uncertain call.

## Original weapon selector and cosmetic labels

The existing type-10 weapon selector stores index 0/1. These mean Manual/Contact
for new throws. Existing saved index 1 therefore starts in Contact; installation
instructions tell users to inspect the selector before throwing. MBM remains
the exclusive source of Throw C4 / Detonate C4 inputs.

The native menu type switch, C4 configuration lookup and label-read path prove
that descriptor offsets 16 and 56 are text IDs, separate from ability IDs and
flags. ModeLabels changes only these two u32s in the verified C4 template. It
claims two empty formatted-text cache slots associated with IDs 0x8bc421a5 and
0xacf702d0, resolved from original getter code. MBM uses the same pool and skips
occupied entries; this implementation never replaces a foreign occupied slot.
Verified formatter paths use cached strings only with zero formatting arguments.
Strings remain pinned through cleanup, including temporary restoration failures.

Installation checks original text IDs, template owner/pointer/hash-slot identity,
code and fresh snapshots; the pre-write record must be flushed. Compare/write
uses WriteProcessMemory on those aligned writable data fields only, reads back
the result, and never changes memory protection. On shutdown/failure, restore
only still-owned fields/slots and retry transient failure. Third-party takeover
is preserved. ActionReader ignores only the two cosmetic IDs when verifying
the descriptor; ability IDs, resource keys and all gameplay flags remain exact.
Label failure is logged independently. In-game font/rendering and compatibility
with additional consumers of the shared text pool still need live validation.

## Validation boundary

Fixtures test real reader layouts, ownership/generation changes, both collision
sides, duplicates, manual/contact coexistence, failed/ambiguous throws, native
request flags, stale snapshots, logging failure, native-call ABI forwarding,
UI/weapon interruption and preservation of the passenger throw lock. Cosmetic
fixtures cover normal install, every partial write failure, retry, takeover,
stale world, descriptor integrity and restoration. Native integration resolves
all signatures against the private captured image, with ASLR checks for existing
paths. Packaging additionally tests the original Arsenal deployment worker.

These are offline checks. Ground/object/character collisions, early airborne
manual detonation, native selector rendering, tank/FRV passenger regression and
multiplayer ownership must still be tested in the actual game before release.

## dev.18 menu-input correction
The dev.17 user test confirmed functional contact detonation but exposed phantom
throws in weapon settings. All nine failed throws in the captured session have
avatar bit 86 and native replacement action 2636; the other nine produce charges.
Native UI stack/cursor remain inactive. The masked fn_flag_86 reader verifies the
same owner/index/0x1238 avatar flags layout as the existing map reader, reading
bit 22 of flags +8 (=86). Native UI lifecycle callers also use this reader; private
mode-ui-* disassemblies preserve those cross-references. This is an observed and
code-verified state, not a physical R-key or vehicle/pose heuristic.

NativeUiGuard now exposes weapon_menu_active; GameplayGuard blocks it before and
after engine update. AvatarScope independently rejects new action/reload
capabilities. Existing suspend logic clears queued input and requires a released
MBM baseline. No writes to the selector, chamber or reserve are introduced.
ContactController still steps independently, so already thrown charges continue
to react to contact during menu use.

The same session reported mode_labels_unavailable: pointer_unavailable on tick 1,
before the player/world managers existed. No cosmetic writes had occurred. Label
acquisition now waits through unavailable startup/context reads and retries when
a selected C4 is present. Code validation, original-field checks, foreign cache
ownership checks and all partial-mutation cleanup remain strict.
