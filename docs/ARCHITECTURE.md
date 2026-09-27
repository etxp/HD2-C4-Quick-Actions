# Architecture — 1.1

- `entry.lua.in` assembles the addon lifecycle, update integration and cleanup. `assemble.py` embeds project modules and creates a separately loaded catalog resource.
- `MBMBindings` and `MBMProfile` integrate official Mod Bindings Menu v2. Physical mouse/controller polling and old Standard/Reversed routes are not used.
- `GameplayGuard`, `NativeUiGuard`, `AvatarScope` and the context/action readers validate selected C4, player ownership, state and interfaces before new actions.
- `NativeResolver` locates masked code signatures and related structures at runtime. It verifies identity and code before calls; no game-build allowlist or whole-module hash gate is used.
- `ActionController` and `ActionBackend` request original native throw/detonate operations. `PassengerHold` retains lean-out through the full throw; `AutoReload` and `PassengerReloadRecovery` handle interruptible reload opportunities.
- `AimInputGate` suppresses overlapping native input paths while preserving release-to-throw aiming. `WeaponFireGate` manages scoped C4 fire-route data and restores owned state.
- `CollisionEvents` reads bounded collision snapshots without advancing the engine iterator. `ContactReader` verifies charge ownership and identity; `ContactController` preserves each charge's selected mode and requests contact detonation once. Manual detonation remains available during flight.
- `ModeLabels` changes the existing C4 selector labels using verified writable data and restores only still-owned entries. No executable code pages are patched or allocated.
- `RollingLog` bounds diagnostics. Context changes revoke pending actions; cleanup releases held input and attempts restoration of owned data.

Runtime guard/catalog details are implementation compatibility checks, not a promise of compatibility with every future game update. Native signature catalogs are included to make the runtime and synthetic tests reproducible. Full game binaries, capture dumps and external mod sources are excluded.

See `NATIVE-AIM.md`, `NATIVE-RELOAD.md` and `NATIVE-CONTACT-RESEARCH.md` for the development rationale; these are dated research notes. Current acceptance scope is in `VALIDATION.md`.
